# typed: false
# frozen_string_literal: true

module PgpArmor
  # Armor constants
  ARMOR_START           = "-----BEGIN "
  ARMOR_END             = "-----END "
  ARMOR_END_OF_LINE     = "-----"
  ARMOR_END_OF_LINE_OUT = "-----\n"
  ARMOR_HEADER_SEP      = ": "
  NEW_LINE              = "\n"
  BLOCK_END             = "\n="

  # ArmorError is raised on armor parsing errors.
  ArmorError = Class.new(ArgumentError)

  def encode(raw, block_type:, headers: {})
    # Add prefix and block type
    encoded = ARMOR_START + block_type + ARMOR_END_OF_LINE_OUT

    # Add headers
    headers.each do |k, v|
      encoded << k.to_s + ARMOR_HEADER_SEP + v.to_s + NEW_LINE
    end

    # Add Base64 encoded data
    b64 = Base64.strict_encode64(raw)
    b64_lines = b64.each_char.each_slice(64).map(&:join)
    encoded << NEW_LINE + b64_lines.join("\n")

    # Add checksum
    encoded << BLOCK_END + crc24_b64(raw)

    # Add suffix
    encoded << NEW_LINE + ARMOR_END + block_type + ARMOR_END_OF_LINE

    encoded
  end

  def decode(encoded)
    lines = encoded.strip.split(/\r?\n/)

    # Check prefix
    line = lines.shift
    bt_start = ARMOR_START.length
    bt_end = line.length - ARMOR_END_OF_LINE.length
    prefix_block_type = line[bt_start...bt_end]

    if prefix_block_type.nil?
      raise ArmorError, "bad prefix"
    end

    # Check suffix
    line = lines.pop
    bt_start = ARMOR_END.length
    bt_end = line.length - ARMOR_END_OF_LINE.length
    suffix_block_type = line[bt_start...bt_end]

    if suffix_block_type.nil? || prefix_block_type != suffix_block_type
      raise ArmorError, "bad suffix"
    end

    # Get headers
    headers = {}
    while (line = lines.shift) != ""
      k, v = line.split(ARMOR_HEADER_SEP, 2)
      headers[k] = v
    end

    # Get CRC
    crc = lines.pop[1..-1]

    # Get data
    data = begin
      Base64.strict_decode64(lines.join)
    rescue ArgumentError
      raise ArmorError, "bad base64 encoding"
    end

    # Check CRC
    if crc24_b64(data) != crc
      raise ArmorError, "invalid CRC"
    end

    [prefix_block_type, headers, data]
  end

  # CRC24 constants
  CRC24_INIT = 0x00B704CE
  CRC24_POLY = 0x01864CFB
  CRC24_MASK = 0x00FFFFFF

  # CRC24 over data as per RFC 4880, section 6.1
  #
  # https://tools.ietf.org/html/rfc4880#section-6.1
  #
  # data - String data to CRC.
  #
  # Returns a 24 bit Integer.
  def crc24(data)
    crc = CRC24_INIT

    data.bytes.each do |byte|
      crc ^= byte << 16

      8.times do |_i|
        crc <<= 1

        if crc & 0x1000000 != 0
          crc ^= CRC24_POLY
        end
      end
    end

    crc & CRC24_MASK
  end

  # Base64 encoded 3 byte big endian representation of CRC24 over data.
  #
  # data - String data to CRC.
  #
  # Returns a String.
  def crc24_b64(data)
    crc = crc24(data)
    le = [crc].pack("L>")[1...4]

    Base64.strict_encode64(le)
  end

  extend self
end
