# frozen_string_literal: true

module Prawn
  # Cache used internally by {Prawn::Document} instances to calculate the width
  # of various strings for layout purposes.
  #
  # @private
  class FontMetricCache
    def initialize(document)
      @document = document

      # font => font size => options => string => width. Fonts are compared by
      # identity: a document reuses one Font object per font, and hashing a
      # font by value is comparatively expensive on this hot path.
      @cache = {}.compare_by_identity
    end

    # Get width of string.
    #
    # @param string [String]
    # @param options [Hash{Symbol => any}]
    # @option options :style [Symbol]
    # @option options :size [Number]
    # @option options :kerning [Boolean] (false)
    # @return [Number]
    def width_of(string, options)
      f =
        if options[:style]
          # override style with :style => :bold
          @document.find_font(@document.font.family, style: options[:style])
        else
          @document.font
        end

      widths = ((@cache[f] ||= {})[@document.font_size] ||= {})[options_key(options)] ||= {}
      encoded_string = nil
      length =
        widths.fetch(string) {
          encoded_string = f.normalize_encoding(string)
          widths[string] = f.compute_width_of(encoded_string, options)
        }

      # Character spacing of exactly 0 adds nothing, so skip counting.
      character_spacing = @document.character_spacing
      unless character_spacing.equal?(0)
        encoded_string ||= f.normalize_encoding(string)
        character_count = @document.font.character_count(encoded_string)
        if character_count.positive?
          length += character_spacing * (character_count - 1)
        end
      end

      length
    end

    # Number of cached widths.
    #
    # @return [Integer]
    def size
      @cache.each_value.sum { |sizes| sizes.each_value.sum { |opts| opts.each_value.sum(&:size) } }
    end

    # Sentinel for "no options were given".
    #
    # @api private
    NO_OPTIONS = :__prawn_no_options__

    # Pre-computed keys for the three values `:kerning` ever takes, so the
    # common case does not have to use the options Hash itself as a Hash key.
    #
    # @api private
    KERNING_KEYS = {
      true => :__prawn_kerning_true__,
      false => :__prawn_kerning_false__,
      nil => :__prawn_kerning_nil__,
    }.freeze

    private

    # Builds the cache key for a set of width options.
    #
    # Using the options Hash itself as a Hash key means every lookup computes
    # Hash#hash and runs Hash#eql? on collisions; together those were ~4.6% of
    # a profiled render. `:kerning` and `:size` are the only options that
    # change the computed width (see Font#compute_width_of), so when one of
    # them is the only key present we can use its value directly. Anything
    # else -- including unusual values -- falls back to the Hash, which is
    # always correct.
    #
    # @api private
    # @param options [Hash]
    # @return [Object] a value usable as a Hash key
    def options_key(options)
      case options.size
      when 0
        NO_OPTIONS
      when 1
        if options.key?(:kerning)
          KERNING_KEYS.fetch(options[:kerning]) { options }
        elsif options.key?(:size)
          # Numeric, so it cannot collide with the Symbol keys above.
          options[:size]
        else
          options
        end
      else
        options
      end
    end
  end
end
