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

      widths = ((@cache[f] ||= {})[@document.font_size] ||= {})[options] ||= {}
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
  end
end
