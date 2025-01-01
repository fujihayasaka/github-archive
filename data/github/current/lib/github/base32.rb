# typed: false
# frozen_string_literal: true

# Unpadded Base32 encoding for Strings!
#
# The String is broken into 5-bit chunks, each representing an Integer index
# into the character set. Every five bytes of input maps to eight bytes of
# output.
#
# For example the String "rails" is encoded like so:
#
# ASCII chars       r   |   a   |   i   |   l   |   s   |
# ASCII bytes      114  |   97  |  105  |  108  |  115  |
# ASCII chunks   -------|-------|-------|-------|-------|
# Bits           0111001001100001011010010110110001110011
# Base32 chunks  ----|----|----|----|----|----|----|----|
# Base32 indices  14 | 9  | 16 | 22 | 18 | 27 | 3  | 19 |
# Base32 chars    O  | J  | Q  | W  | S  | 3  | D  | T  |
#
# GitHub::Base32.encode("rails")
# => "OJQWS3DT"
#
module GitHub::Base32
  # https://tools.ietf.org/html/rfc4648#page-9
  DEFAULT_CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  NULL = String.new("\x00", encoding: Encoding::ASCII_8BIT)

  # Encode a String as unpadded Base32.
  #
  # Padding is not included because the RFC says that it doesn't need to be.
  # https://tools.ietf.org/html/rfc4648#section-3.2
  #
  # raw     - The raw String to encode.
  # charset - The 32 byte String of characters to use for encoding.
  #
  # Returns an encoded String.
  def encode(raw, charset: DEFAULT_CHARSET)
    # Add extra characters to make size divisible by 5.
    padding = 5 - raw.bytesize % 5
    padding = 0 if padding == 5
    raw = raw + NULL * padding

    indices = raw.each_byte.each_slice(5).map do |chunk|
      # The five 8-bit characters are combined into a single 40 bit number.
      n = (chunk[0] << 32) +
          (chunk[1] << 24) +
          (chunk[2] << 16) +
          (chunk[3] << 8)  +
          (chunk[4] << 0)

      # The single 40 bit number is broken into eight 5-bit numbers.
      [
        (n >> 35) & 0b11111,
        (n >> 30) & 0b11111,
        (n >> 25) & 0b11111,
        (n >> 20) & 0b11111,
        (n >> 15) & 0b11111,
        (n >> 10) & 0b11111,
        (n >> 5)  & 0b11111,
        (n >> 0)  & 0b11111,
      ]
    end.flatten

    # Remove bytes that only represent padding.
    junk_bytes = (padding * 8.0 / 5.0).floor
    good_bytes = indices.size - junk_bytes
    indices.slice!(good_bytes..-1)

    # Map indices into the charset.
    indices.map { |i| charset[i] }.join
  end

  # Encode a String as Base32.
  #
  # encoded - The unpadded Base32 encoded String to decode.
  # charset - The 32 byte String of characters to use for encoding.
  #
  # Returns a decoded String.
  def decode(encoded, charset: DEFAULT_CHARSET)
    raise ArgumentError unless encoded.is_a?(String)

    # Add extra characters to make size divisible by 8.
    padding = 8 - encoded.bytesize % 8
    padding = 0 if padding == 8
    encoded = encoded + charset[0] * padding

    # Map charset to indices.
    indices = encoded.each_char.map { |c| charset.index(c) }

    # The string wasn't encoded with this charset.
    if indices.include?(nil)
      raise ArgumentError, "string encoded with different charset"
    end

    bytes = indices.each_slice(8).map do |chunk|
      # The eight 5-bit characters are combined into a single 40 bit number.
      n = (chunk[0] << 35) +
          (chunk[1] << 30) +
          (chunk[2] << 25) +
          (chunk[3] << 20) +
          (chunk[4] << 15) +
          (chunk[5] << 10) +
          (chunk[6] << 5)  +
          (chunk[7] << 0)

      # The single 40 bit number is broken into five 8-bit numbers.
      [
        (n >> 32) & 0b11111111,
        (n >> 24) & 0b11111111,
        (n >> 16) & 0b11111111,
        (n >> 8)  & 0b11111111,
        (n >> 0)  & 0b11111111,
      ]
    end.flatten

    # Remove padding bytes.
    junk_bytes = (padding * 5.0 / 8.0).ceil
    good_bytes = bytes.size - junk_bytes
    bytes.slice!(good_bytes..-1)

    # Map bytes into an ASCII string.
    bytes.pack("C*")
  end

  extend self
end
