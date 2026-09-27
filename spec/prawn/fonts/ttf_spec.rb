# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

describe Prawn::Fonts::TTF do
  describe 'parsed file cache' do
    let(:font_path) { "#{Prawn::DATADIR}/fonts/DejaVuSans.ttf" }

    before { described_class.clear_parsed_file_cache }

    after do
      described_class.cache_parsed_files = true
      described_class.clear_parsed_file_cache
    end

    def ttf_for(source)
      pdf = Prawn::Document.new
      pdf.font(source)
      pdf.font.ttf
    end

    it 'reuses the parsed file across documents in the same thread' do
      expect(ttf_for(font_path)).to equal(ttf_for(font_path))
    end

    it 'shares the entry between a String path and a Pathname' do
      expect(ttf_for(font_path)).to equal(ttf_for(Pathname.new(font_path)))
    end

    it 'parses the file separately in each thread' do
      here = ttf_for(font_path)
      there = Thread.new { ttf_for(font_path) }.value

      expect(there).to_not equal(here)
    end

    it 'parses the file again when it has been modified' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'font.ttf')
        FileUtils.cp(font_path, path)
        first = ttf_for(path)

        File.utime(Time.now, File.mtime(path) + 60, path)

        expect(ttf_for(path)).to_not equal(first)
      end
    end

    it 'does not cache fonts loaded from IO objects' do
      ttfs =
        Array.new(2) {
          File.open(font_path, 'rb') do |io|
            pdf = Prawn::Document.new
            Prawn::Font.load(pdf, io).ttf
          end
        }

      expect(ttfs.first).to_not equal(ttfs.last)
    end

    it 'can be disabled' do
      described_class.cache_parsed_files = false

      expect(ttf_for(font_path)).to_not equal(ttf_for(font_path))
    end

    def render_sample
      Prawn::Document.new(info: { CreationDate: Time.utc(2026, 1, 1) }) { |pdf|
        pdf.font(font_path)
        pdf.text('Cached fonts render identically: ÀÉÎÕÜ ñ')
      }.render
    end

    it 'renders the same document with a cached font' do
      described_class.cache_parsed_files = false
      uncached = render_sample
      described_class.cache_parsed_files = true
      render_sample # populate the cache

      expect(render_sample).to eq(uncached)
    end
  end
end
