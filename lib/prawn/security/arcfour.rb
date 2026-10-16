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
    # 1. Allocate an 256 element array of 8 bit bytes to be used as an S-box
    # 2. Initialize the S-box.  Fill each entry first with it's index
    sbox = SBOX_TEMPLATE.dup

    # 3. Set j to zero and initialize the S-box, repeating key bytes as
    #    necessary without allocating intermediate unpacked/expanded arrays.
    j = 0
    i = 0
    if key.is_a?(String)
      key_len = key.bytesize
      while i < 256
        j = (j + sbox[i] + key.getbyte(i % key_len)) & 0xff
        sbox[i], sbox[j] = sbox[j], sbox[i]
        i += 1
      end
    else
      key_len = key.length
      while i < 256
        j = (j + sbox[i] + key[i % key_len]) & 0xff
        sbox[i], sbox[j] = sbox[j], sbox[i]
        i += 1
      end
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
    out = ''.b

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
