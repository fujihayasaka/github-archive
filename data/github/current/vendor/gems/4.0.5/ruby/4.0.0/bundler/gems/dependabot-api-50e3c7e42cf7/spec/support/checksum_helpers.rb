# frozen_string_literal: true

module ChecksumHelpers
  def valid_checksum?(token)
    return false if token.blank?

    provided_checksum = token[-6..]
    return false if provided_checksum.blank?

    # This is the token without the prefix
    checksum_string = token.split("_", 2).last
    # This is the token without the checksum
    checksum_string = checksum_string[0..-7]
    return false if checksum_string.blank?

    calculated_checksum = checksum(checksum_string)
    calculated_checksum == provided_checksum
  end

  def checksum(token)
    crc_value = Zlib.crc32(token)
    base62_str = Base62.encode(crc_value)
    base62_str.rjust(6, Base62::PRIMITIVES[0])
  end
end
