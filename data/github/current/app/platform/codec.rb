# typed: true
# frozen_string_literal: true

module Platform
  # Encode hashes to a compact string with no `:` chars
  # (since these are a channel field delimiter)
  module Codec
    PACKER = MessagePack::Factory.new
    def self.encode(obj)
      Base64.strict_encode64(
        PACKER.pack(
          GitHub::JSON.canonicalize(
            obj
          )
        )
      )
    end

    def self.decode(str)
      PACKER.unpack(
        Base64.strict_decode64(
          str
        )
      )
    end
  end
end
