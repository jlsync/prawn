# frozen_string_literal: true

require 'benchmark'

# Minimal constants used by LineWrap helpers
module Prawn
  module Text
    SHY = "\u00AD"
    ZWSP = "\u200B"
  end
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'prawn/text/formatted/line_wrap'

# A minimal shim to access the helper methods without full Prawn dependencies
Cached = Prawn::Text::Formatted::LineWrap

# Uncached version of just the helper methods we optimized
class Uncached
  def soft_hyphen(encoding = ::Encoding::UTF_8)
    Prawn::Text::SHY.encode(encoding)
  rescue ::Encoding::InvalidByteSequenceError, ::Encoding::UndefinedConversionError
    nil
  end

  def zero_width_space(encoding = ::Encoding::UTF_8)
    Prawn::Text::ZWSP.encode(encoding)
  rescue ::Encoding::InvalidByteSequenceError, ::Encoding::UndefinedConversionError
    nil
  end

  def whitespace(encoding = ::Encoding::UTF_8)
    "\s\t#{zero_width_space(encoding)}".encode(encoding)
  end

  def hyphen(_encoding = ::Encoding::UTF_8)
    '-'
  rescue ::Encoding::InvalidByteSequenceError, ::Encoding::UndefinedConversionError
    nil
  end

  def break_chars(encoding = ::Encoding::UTF_8)
    [
      whitespace(encoding),
      soft_hyphen(encoding),
      hyphen(encoding),
    ].join('')
  end

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

    pattern = patterns
      .map { |p| p.encode(encoding) }
      .join('|')

    Regexp.new(pattern)
  end

  def word_division_scan_pattern(encoding = ::Encoding::UTF_8)
    common_whitespaces = ["\t", "\n", "\v", "\r", ' '].map { |c| c.encode(encoding) }
    Regexp.union(
      common_whitespaces + [zero_width_space(encoding), soft_hyphen(encoding), hyphen(encoding)].compact,
    )
  end

  def breakable_start_regex(encoding)
    Regexp.new("^[#{break_chars(encoding)}]")
  end

  def breakable_end_regex(encoding)
    Regexp.new("[#{break_chars(encoding)}]$")
  end

  def last_word_regex(encoding)
    Regexp.new("[^#{break_chars(encoding)}]*$")
  end
end

iterations = 50_000
encodings = [Encoding::UTF_8]

puts "Iterations: #{iterations}, Encodings: #{encodings.map(&:name).join(', ')}"

Benchmark.bmbm do |x|
  x.report('scan_pattern uncached') do
    u = Uncached.new
    iterations.times do
      encodings.each { |e| u.scan_pattern(e) }
    end
  end

  x.report('scan_pattern cached') do
    c = Cached.new
    iterations.times do
      encodings.each { |e| c.send(:scan_pattern, e) }
    end
  end

  x.report('word_division_pattern uncached') do
    u = Uncached.new
    iterations.times do
      encodings.each { |e| u.word_division_scan_pattern(e) }
    end
  end

  x.report('word_division_pattern cached') do
    c = Cached.new
    iterations.times do
      encodings.each { |e| c.send(:word_division_scan_pattern, e) }
    end
  end

  x.report('break_start_regex uncached') do
    u = Uncached.new
    iterations.times do
      encodings.each { |e| u.breakable_start_regex(e) }
    end
  end

  x.report('break_start_regex cached') do
    c = Cached.new
    iterations.times do
      encodings.each { |e| c.send(:breakable_start_regex, e) }
    end
  end

  x.report('break_end_regex uncached') do
    u = Uncached.new
    iterations.times do
      encodings.each { |e| u.breakable_end_regex(e) }
    end
  end

  x.report('break_end_regex cached') do
    c = Cached.new
    iterations.times do
      encodings.each { |e| c.send(:breakable_end_regex, e) }
    end
  end

  x.report('last_word_regex uncached') do
    u = Uncached.new
    iterations.times do
      encodings.each { |e| u.last_word_regex(e) }
    end
  end

  x.report('last_word_regex cached') do
    c = Cached.new
    iterations.times do
      encodings.each { |e| c.send(:last_word_regex, e) }
    end
  end

  segments = %w[Hello \u00AD world - text 123 abcdefghijklmnop].map { |s| s.encode(Encoding::UTF_8) }
  x.report('append via +=') do
    iterations.times do
      out = +''
      segments.each { |seg| out += seg }
    end
  end

  x.report('append via <<') do
    iterations.times do
      out = +''
      segments.each { |seg| out << seg }
    end
  end
end
