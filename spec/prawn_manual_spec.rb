# frozen_string_literal: true

require 'spec_helper'
require 'digest/sha2'

MANUAL_HASH =
  case RUBY_ENGINE
  when 'ruby'
    '9b49e37d52c13a0a482be417ab8b7d463dc98844e5ea2a606eda83a0b673a6f5f30ae003406bee05d4ab7e56ecfa45b9b72a0992608c9d66ffb3bcef72e05475'
  when 'jruby'
    '1aa45e7898e9ca383f02c8beb0f877fa1f27c124ff0f9911061fcb862c5cdb41c5ce78efa30b0f17af924d78c7a66394c45988211778f6a171ae0d1a271d4815'
  end

RSpec.describe Prawn do
  describe 'manual' do
    # JRuby's zlib is a bit quirky. It sometimes produces different output to
    # libzlib (used by MRI). It's still a proper deflate stream and can be
    # decompressed just fine but for whatever reason compressin produses
    # different output.
    #
    # See: https://github.com/jruby/jruby/issues/4244
    it 'contains no unexpected changes' do
      ENV['CI'] ||= 'true'

      manual_path = File.expand_path('../manual/manual.rb', __dir__)
      manual = eval(File.read(manual_path), TOPLEVEL_BINDING, manual_path) # rubocop: disable Security/Eval
      s = manual.generate

      hash = Digest::SHA512.hexdigest(s)

      expect(hash).to eq MANUAL_HASH
    end
  end
end
