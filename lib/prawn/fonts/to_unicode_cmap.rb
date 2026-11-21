# frozen_string_literal: true

module Prawn
  module Fonts
    # This class generates ToUnicode CMap for embedde TrueType/OpenType fonts.
    # It's a separate format and is somewhat complicated so it has its own
    # place.
    #
    # @private
    class ToUnicodeCMap
      # mapping is expected to be a hash with keys being character codes (in
      # broad sense, as used in the showing operation strings) and values being
      # Unicode code points.
      def initialize(mapping, code_space_size = nil)
        @mapping = mapping
        @code_space_size = code_space_size
      end

      # Generate CMap.
      #
      # @return [String]
      def generate
        chunks = []

        # Header
        chunks << <<~HEADER.chomp
          /CIDInit /ProcSet findresource begin
          12 dict begin
          begincmap
          /CIDSystemInfo 3 dict dup begin
            /Registry (Adobe) def
            /Ordering (UCS) def
            /Supplement 0 def
          end def
          /CMapName /Adobe-Identity-UCS def
          /CMapType 2 def
        HEADER

        max_glyph_index = mapping.keys.max
        # Range
        code_space_size = (max_glyph_index.bit_length / 8.0).ceil

        used_code_space_size = @code_space_size || code_space_size

        # In CMap codespaces are not sequentional, they're ranges in
        # a multi-dimentional space. Each byte is considered separately. So we
        # have to maximally extend the lower bytes in order to allow for
        # continuos mapping.
        # We only keep the highest byte because usually it's lower than
        # maximally allowed and we don't want to cover that unused space.
        code_space_max = max_glyph_index | ('ff' * (code_space_size - 1)).to_i(16)

        chunks << '1 begincodespacerange'
        # rubocop: disable Lint/FormatParameterMismatch -- false positive
        chunks << format("<%0#{used_code_space_size * 2}X><%0#{used_code_space_size * 2}X>", 0, code_space_max)
        # rubocop: enable Lint/FormatParameterMismatch
        chunks << 'endcodespacerange'

        # Mapping
        filtered = []
        mapping.each do |gid, cid|
          next if gid.zero? || cid.between?(0xd800, 0xdfff)

          filtered << [gid, cid]
        end
        filtered.sort!
        all_spans = mapping_spans(filtered, presorted: true)

        short_spans, long_spans = all_spans.partition { |span| span[0] == :short }

        hex_width = code_space_size * 2
        formats = {
          fully_sorted_bmp: "<%0#{hex_width}X><%0#{hex_width}X><%04x>",
          fully_sorted: "<%0#{hex_width}X><%0#{hex_width}X><%s>",
          index_sorted: "<%0#{hex_width}X><%0#{hex_width}X>[%s]",
          char_bmp: "<%0#{hex_width}X><%04x>",
          char: "<%0#{hex_width}X><%s>",
        }

        append_long_spans(chunks, long_spans, formats)
        append_short_spans(chunks, short_spans, formats)

        # Footer
        chunks << <<~FOOTER.chomp
          endcmap
          CMapName currentdict /CMap defineresource pop
          end
          end
        FOOTER

        chunks.join("\n")
      end

      private

      attr_reader :mapping

      attr_reader :cmap
      attr_reader :code_space_size
      attr_reader :code_space_max

      def append_long_spans(chunks, long_spans, formats)
        long_spans.each_slice(100) do |spans|
          chunks << "#{spans.length} beginbfrange"
          spans.each do |type, span|
            chunks << format_bfrange_span(type, span, formats)
          end
          chunks << 'endbfrange'
        end
      end

      def format_bfrange_span(type, span, formats)
        case type
        when :fully_sorted
          cid = span.first[1]
          if cid <= 0xFFFF
            format(formats[:fully_sorted_bmp], span.first[0], span.last[0], cid)
          else
            format(
              formats[:fully_sorted],
              span.first[0],
              span.last[0],
              cid.chr(::Encoding::UTF_16BE).unpack1('H*'),
            )
          end
        when :index_sorted
          values = +''
          span.each do |pair|
            cid = pair[1]
            if cid <= 0xFFFF
              values << format('<%04x>', cid)
            else
              values << '<' << cid.chr(::Encoding::UTF_16BE).unpack1('H*') << '>'
            end
          end
          format(formats[:index_sorted], span.first[0], span.last[0], values)
        end
      end

      def append_short_spans(chunks, short_spans, formats)
        short_spans.each_slice(100) do |batch|
          chunks << "#{batch.length} beginbfchar"
          batch.each do |entry|
            gid, cid = entry[1][0]
            chunks <<
              if cid <= 0xFFFF
                format(formats[:char_bmp], gid, cid)
              else
                format(
                  formats[:char],
                  gid,
                  cid.chr(::Encoding::UTF_16BE).unpack1('H*'),
                )
              end
          end
          chunks << 'endbfchar'
        end
      end

      def mapping_spans(mapping, presorted: false)
        (presorted ? mapping : mapping.sort)
          .slice_when { |a, b| (b[0] - a[0]) != 1 } # Slice at key discontinuity
          .flat_map { |slice|
            if slice.length == 1
              [[:short, slice]]
            else
              continuous_slices, discontinuous_slices =
                slice
                  .slice_when { |a, b| b[1] - a[1] != 1 } # Slice at value discontinuity
                  .partition { |subslice| subslice.length > 1 }

              discontinuous_slices
                .flatten(1) # Join together
                .slice_when { |a, b| (b[0] - a[0]) != 1 } # Slice at key discontinuity, again
                .map { |span| span.length > 1 ? [:index_sorted, span] : [:short, slice] } +
                continuous_slices.map { |span| [:fully_sorted, span] }
            end
          } # rubocop: disable Style/MultilineBlockChain
          .sort_by { |span| span[1][0][0] } # Sort span start key
      end
    end
  end
end
