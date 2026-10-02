# frozen_string_literal: true

# Implementation of the "ARCFOUR" algorithm ("alleged RC4 (tm)"). Implemented
# as described at:
# http://www.mozilla.org/projects/security/pki/nss/draft-kaukonen-cipher-arcfour-03.txt
#
# "RC4" is a trademark of RSA Data Security, Inc.
#
# @private
class Arcfour
  # A fresh copy per instance: the S-box is permuted in place below.
  SBOX_TEMPLATE = (0..255).to_a.freeze
  private_constant :SBOX_TEMPLATE

  def initialize(key)
    # Convert string key to Array of integers
    key = key.unpack('c*') if key.is_a?(String)

    # 1. Allocate an 256 element array of 8 bit bytes to be used as an S-box
    # 2. Initialize the S-box.  Fill each entry first with it's index
    sbox = SBOX_TEMPLATE.dup

    # 3. Fill another array of the same size (256) with the key, repeating
    #    bytes as necessary.
    s2 = key * ((255 / key.length) + 1)

    # 4. Set j to zero and initialize the S-box
    j = 0
    i = 0
    while i < 256
      j = (j + sbox[i] + s2[i]) & 0xff
      sbox[i], sbox[j] = sbox[j], sbox[i]
      i += 1
    end

    @sbox = sbox
    @i = @j = 0
  end

  # Encrypt string.
  #
  # @param string [String]
  # @return [String]
  def encrypt(string)
    sbox = @sbox
    i = @i
    j = @j
    out = String.new(capacity: string.bytesize, encoding: ::Encoding::BINARY)

    # The keystream loop is inlined here: this runs once per byte of every
    # encrypted string, and #key_byte would be a method call per byte.
    string.each_byte do |byte|
      i = (i + 1) & 0xff
      j = (j + sbox[i]) & 0xff
      sbox[i], sbox[j] = sbox[j], sbox[i]
      out << (byte ^ sbox[(sbox[i] + sbox[j]) & 0xff])
    end

    @i = i
    @j = j
    out
  end
end
