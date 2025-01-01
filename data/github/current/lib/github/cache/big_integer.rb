# typed: true
# frozen_string_literal: true

module GitHub
  module Cache

    # So why does this class exist? Well, msgpack ends does
    # not allow caching arbitrary big integers, only signed or
    # unsigned values up to 64 bits.
    #
    # This class wraps a custom serializer so we can also cache
    # larger and smaller values.
    class BigInteger
      def initialize(value)
        @value = value
      end

      def to_int
        @value
      end

      def to_s
        @value.to_s
      end

      PACKER = lambda do |value|
        GitHub::Cache::Codec.factory.pack(value.to_s)
      end

      UNPACKER = lambda do |data|
        GitHub::Cache::Codec.factory.unpack(data).to_i
      end

      GitHub::Cache::Codec.register_type(GitHub::Cache::Codec::BIG_INTEGER_TYPE, self)
    end
  end
end
