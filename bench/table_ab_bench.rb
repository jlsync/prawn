# frozen_string_literal: true

require 'benchmark'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'prawn'
require 'prawn/table'

# Helpers for data
class String
  CHARS = ('a'..'z').to_a
  def self.random(length)
    Array.new(length) { CHARS.sample }.join
  end
end

def data_for_table(columns, rows, string_size)
  Array.new(rows) { Array.new(columns) { String.random(string_size) } }
end

def measure(label)
  t = Benchmark.realtime { yield }
  puts format('%-40s %.3fs', label + ':', t)
end

def render_table_case
  data = data_for_table(26, 50, 10)
  opts = { row_colors: %w[FFFFFF F0F0FF], header: true, cell_style: { inline_format: true } }
  Prawn::Document.new { table(data, opts) }.render
end

# Monkey-patch to simulate pre-change (uncached) behavior
module UncachedLineWrapPatch
  def scan_pattern(encoding = ::Encoding::UTF_8)
    ebc = break_chars(encoding)
    eshy = soft_hyphen(encoding)
    ehy = hyphen(encoding)
    ews = whitespace(encoding)

    patterns = [
      "[^#{ebc}]+#{eshy}",
      "[^#{ebc}]+#{ehy}+",
      "[^#{ebc}]+",
      "[#{ews}]+",
      "#{ehy}+[^#{ebc}]*",
      eshy.to_s,
    ]

    pattern = patterns.map { |p| p.encode(encoding) }.join('|')
    Regexp.new(pattern)
  end

  def word_division_scan_pattern(encoding = ::Encoding::UTF_8)
    common_whitespaces = ["\t", "\n", "\v", "\r", ' '].map { |c| c.encode(encoding) }
    Regexp.union(common_whitespaces + [zero_width_space(encoding), soft_hyphen(encoding), hyphen(encoding)].compact)
  end

  def break_chars(encoding = ::Encoding::UTF_8)
    [whitespace(encoding), soft_hyphen(encoding), hyphen(encoding)].join('')
  end

  def remember_this_fragment_for_backward_looking_ops
    @previous_fragment = @fragment_output.dup
    pf = @previous_fragment
    @previous_fragment_ended_with_breakable = /[#{break_chars(pf.encoding)}]$/.match?(pf)
    last_word = pf.slice(/[^#{break_chars(pf.encoding)}]*$/)
    last_word_length = last_word.nil? ? 0 : last_word.length
    @previous_fragment_output_without_last_word = pf.slice(0, pf.length - last_word_length)
  end

  def fragment_begins_with_breakable?(fragment)
    /^[#{break_chars(fragment.encoding)}]/.match?(fragment)
  end

  # Re-define add_fragment_to_line to use "+=" for appends
  def add_fragment_to_line(fragment)
    case fragment
    when ''
      true
    when "\n"
      @newline_encountered = true
      false
    else
      tokenize(fragment).each do |segment|
        segment_width =
          if segment == zero_width_space(segment.encoding)
            0
          else
            @document.width_of(segment, kerning: @kerning)
          end

        if @accumulated_width + segment_width <= @width
          @accumulated_width += segment_width
          shy = soft_hyphen(segment.encoding)
          if segment[-1] == shy
            sh_width = @document.width_of(shy, kerning: @kerning)
            @accumulated_width -= sh_width
          end
          @fragment_output += segment
        else
          if @accumulated_width.zero? && @line_contains_more_than_one_word
            @line_contains_more_than_one_word = false
          end
          end_of_the_line_reached(segment)
          fragment_finished(fragment)
          return false
        end
      end

      fragment_finished(fragment)
      true
    end
  end
end

def with_uncached_line_wrap
  klass = Prawn::Text::Formatted::LineWrap
  origs = {}
  methods = %i[
    scan_pattern word_division_scan_pattern break_chars
    remember_this_fragment_for_backward_looking_ops fragment_begins_with_breakable?
    add_fragment_to_line
  ]
  methods.each { |m| origs[m] = klass.instance_method(m) }
  klass.prepend(UncachedLineWrapPatch)
  yield
ensure
  methods.each do |m|
    klass.send(:define_method, m, origs[m])
  end
end

puts 'A/B benchmark on table rendering (26x50, inline_format)'
measure('Cached (current)') { render_table_case }
with_uncached_line_wrap do
  measure('Uncached (pre-change approx)') { render_table_case }
end

