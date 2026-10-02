# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'stringio'
module Prawn
  module Images # rubocop: disable Style/Documentation
    # A convenience class that wraps the logic for extracting the parts of a PNG
    # image that we need to embed them in a PDF.
    class PNG < Image
      # @group Extension API

      # Palette data.
      # @return [String]
      attr_reader :palette

      # Image data.
      # @return [String]
      attr_reader :img_data

      # Transparency data.
      # @return [Hash{Symbol => String}]
      attr_reader :transparency

      # Image width in pixels.
      # @return [Integer]
      attr_reader :width

      # Image height in pixels.
      # @return [Integer]
      attr_reader :height

      # Bits per sample or per palette index.
      # @return [Integer]
      attr_reader :bits

      # Color type.
      # @return [Integer]
      attr_reader :color_type

      # Compression method.
      # @return [Integer]
      attr_reader :compression_method

      # Filter method.
      # @return [Integer]
      attr_reader :filter_method

      # Interlace method.
      # @return [Integer]
      attr_reader :interlace_method

      # Extracted alpha-channel.
      # @return [String, nil]
      attr_reader :alpha_channel

      # Scaled width of the image in PDF points.
      # @return [Number]
      attr_accessor :scaled_width

      # Scaled height of the image in PDF points.
      # @return [Number]
      attr_accessor :scaled_height

      PNG_MAGIC = "\x89PNG\r\n\x1a\n".b.freeze
      private_constant :PNG_MAGIC

      # Can this image handler process this image?
      #
      # @param image_blob [String]
      # @return [Boolean]
      def self.can_render?(image_blob)
        if image_blob.encoding == ::Encoding::BINARY
          image_blob.start_with?(PNG_MAGIC)
        else
          image_blob.byteslice(0, 8)&.b == PNG_MAGIC
        end
      end

      # Process a new PNG image
      #
      # @param data [String] A binary string of PNG data.
      def initialize(data)
        super()
        data = StringIO.new(data.dup)

        data.read(8) # Skip the default header

        @palette = +''
        @img_data = +''
        @transparency = {}

        loop do
          chunk_size = data.read(4).unpack1('N')
          section = data.read(4)
          case section
          when 'IHDR'
            # we can grab other interesting values from here (like width,
            # height, etc)
            values = data.read(chunk_size).unpack('NNCCCCC')

            @width = values[0]
            @height = values[1]
            @bits = values[2]
            @color_type = values[3]
            @compression_method = values[4]
            @filter_method = values[5]
            @interlace_method = values[6]
          when 'PLTE'
            @palette << data.read(chunk_size)
          when 'IDAT'
            @img_data << data.read(chunk_size)
          when 'tRNS'
            # This chunk can only occur once and it must occur after the
            # PLTE chunk and before the IDAT chunk
            @transparency = {}
            case @color_type
            when 3
              @transparency[:palette] = data.read(chunk_size).unpack('C*')
            when 0
              # Greyscale. Corresponding to entries in the PLTE chunk.
              # Grey is two bytes, range 0 .. (2 ^ bit-depth) - 1
              grayval = data.read(chunk_size).unpack1('n')
              @transparency[:grayscale] = grayval
            when 2
              # True colour with proper alpha channel.
              @transparency[:rgb] = data.read(chunk_size).unpack('nnn')
            end
          when 'IEND'
            # we've got everything we need, exit the loop
            break
          else
            # unknown (or un-important) section, skip over it
            data.seek(data.pos + chunk_size)
          end

          data.read(4) # Skip the CRC
        end

        @img_data = Zlib::Inflate.inflate(@img_data)
      end

      # Number of color components to each pixel.
      #
      # @return [Integer]
      def colors
        case color_type
        when 0, 3, 4
          1
        when 2, 6
          3
        end
      end

      # Split the alpha channel data from the raw image data in images where
      # it's required.
      #
      # @private
      # @return [void]
      def split_alpha_channel!
        if alpha_channel?
          if color_type == 3
            generate_alpha_channel
          else
            split_image_data
          end
        end
      end

      # Is there an alpha-channel in this image?
      #
      # @return [Boolean]
      def alpha_channel?
        return true if [4, 6].include?(color_type)
        return @transparency.any? if color_type == 3

        false
      end

      # Build a PDF object representing this image in `document`, and return
      # a Reference to it.
      #
      # @param document [Prawn::Document]
      # @return [PDF::Core::Reference]
      def build_pdf_object(document)
        if compression_method != 0
          raise Errors::UnsupportedImageType,
            'PNG uses an unsupported compression method'
        end

        if filter_method != 0
          raise Errors::UnsupportedImageType,
            'PNG uses an unsupported filter method'
        end

        if interlace_method != 0
          raise Errors::UnsupportedImageType,
            'PNG uses unsupported interlace method'
        end

        # some PNG types store the colour and alpha channel data together,
        # which the PDF spec doesn't like, so split it out.
        split_alpha_channel!

        case colors
        when 1
          color = :DeviceGray
        when 3
          color = :DeviceRGB
        else
          raise Errors::UnsupportedImageType,
            "PNG uses an unsupported number of colors (#{png.colors})"
        end

        # build the image dict
        obj = document.ref!(
          Type: :XObject,
          Subtype: :Image,
          Height: height,
          Width: width,
          BitsPerComponent: bits,
        )

        # append the actual image data to the object as a stream
        obj << img_data

        obj.stream.filters << {
          FlateDecode: {
            Predictor: 15,
            Colors: colors,
            BitsPerComponent: bits,
            Columns: width,
          },
        }

        # sort out the colours of the image
        if palette.empty?
          obj.data[:ColorSpace] = color
        else
          # embed the colour palette in the PDF as an object stream
          palette_obj = document.ref!({})
          palette_obj << palette

          # build the color space array for the image
          obj.data[:ColorSpace] = [
            :Indexed,
            :DeviceRGB,
            (palette.size / 3) - 1,
            palette_obj,
          ]
        end

        # *************************************
        # add transparency data if necessary
        # *************************************

        # For PNG color types 0, 2 and 3, the transparency data is stored in
        # a dedicated PNG chunk, and is exposed via the transparency attribute
        # of the PNG class.
        if transparency[:grayscale]
          # Use Color Key Masking (spec section 4.8.5)
          # - An array with N elements, where N is two times the number of color
          #   components.
          val = transparency[:grayscale]
          obj.data[:Mask] = [val, val]
        elsif transparency[:rgb]
          # Use Color Key Masking (spec section 4.8.5)
          # - An array with N elements, where N is two times the number of color
          #   components.
          rgb = transparency[:rgb]
          obj.data[:Mask] = rgb.map { |x| [x, x] }.flatten
        end

        # For PNG color types 4 and 6, the transparency data is stored as
        # an alpha channel mixed in with the main image data. The PNG class
        # separates it out for us and makes it available via the alpha_channel
        # attribute
        if alpha_channel?
          smask_obj = document.ref!(
            Type: :XObject,
            Subtype: :Image,
            Height: height,
            Width: width,
            BitsPerComponent: bits,
            ColorSpace: :DeviceGray,
            Decode: [0, 1],
          )
          smask_obj.stream << alpha_channel

          smask_obj.stream.filters << {
            FlateDecode: {
              Predictor: 15,
              Colors: 1,
              BitsPerComponent: bits,
              Columns: width,
            },
          }
          obj.data[:SMask] = smask_obj
        end

        obj
      end

      # Returns the minimum PDF version required to support this image.
      #
      # @return [Float]
      def min_pdf_version
        if bits > 8
          # 16-bit color only supported in 1.5+ (ISO 32000-1:2008 8.9.5.1)
          1.5
        elsif alpha_channel?
          # Need transparency for SMask
          1.4
        else
          1.0
        end
      end

      private

      def split_image_data
        alpha_bytes = bits / 8
        color_bytes = colors * bits / 8

        scanline_length = ((color_bytes + alpha_bytes) * width) + 1
        source = @img_data
        scanlines = source.bytesize / scanline_length
        pixels = width * height

        color_size = (pixels * color_bytes) + scanlines
        alpha_size = (pixels * alpha_bytes) + scanlines
        # Build the channels by appending, rather than pre-sizing zero-filled
        # buffers and copying each pixel through a StringIO. The buffers are
        # zero padded below if the data runs short, matching the old output.
        color_data = String.new(capacity: color_size, encoding: ::Encoding::BINARY)
        alpha_data = String.new(capacity: alpha_size, encoding: ::Encoding::BINARY)

        position = 0
        scanlines.times do
          filter = source.getbyte(position)
          position += 1
          color_data << filter
          alpha_data << filter

          width.times do
            color_data <<
              if color_bytes == 1
                source.getbyte(position)
              else
                source.byteslice(position, color_bytes)
              end
            position += color_bytes

            alpha_data <<
              if alpha_bytes == 1
                source.getbyte(position)
              else
                source.byteslice(position, alpha_bytes)
              end
            position += alpha_bytes
          end
        end

        if color_data.bytesize < color_size
          color_data << ("\0".b * (color_size - color_data.bytesize))
        end
        if alpha_data.bytesize < alpha_size
          alpha_data << ("\0".b * (alpha_size - alpha_data.bytesize))
        end

        @img_data = color_data
        @alpha_channel = alpha_data
      end

      def generate_alpha_channel
        # An Array default is a cheaper lookup than a Hash default at one
        # lookup per pixel. Size 256 keeps the 0xff default for every possible
        # palette index even when tRNS is partial.
        alpha_palette = Array.new(256, 0xff)
        palette_entries = palette.bytesize / 3
        0.upto(palette_entries) do |n|
          alpha_palette[n] = @transparency[:palette][n] || 0xff
        end

        source = @img_data
        scanline_length = width + 1
        scanlines = source.bytesize / scanline_length
        pixels = width * height

        alpha_size = pixels + scanlines
        alpha_data = String.new(capacity: alpha_size, encoding: ::Encoding::BINARY)

        position = 0
        scanlines.times do
          alpha_data << source.getbyte(position)
          position += 1

          width.times do
            alpha_data << alpha_palette[source.getbyte(position)]
            position += 1
          end
        end

        if alpha_data.bytesize < alpha_size
          alpha_data << ("\0".b * (alpha_size - alpha_data.bytesize))
        end

        @alpha_channel = alpha_data
      end
    end

    Prawn.image_handler.register(Prawn::Images::PNG)
  end
end
