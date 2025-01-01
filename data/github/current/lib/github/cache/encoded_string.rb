# typed: true
# frozen_string_literal: true

module GitHub
  module Cache

    # MessagePack doesn't have arbitrary string encoding.
    # Since Git data can be arbitrary encoded, we need to handle
    # that case as well which is why we wrap this here.
    class EncodedString
      def initialize(str)
        @str = str
      end

      def to_str
        @str
      end

      def to_s
        to_str
      end

      PACKER = lambda do |obj|
        str = obj.to_str
        GitHub::Cache::Codec.factory.pack([str.encoding.name, str.b])
      end

      UNPACKER = lambda do |data|
        encoding, str = GitHub::Cache::Codec.factory.unpack(data)
        str.force_encoding(encoding)
      end

      GitHub::Cache::Codec.register_type(GitHub::Cache::Codec::ENCODED_STRING_TYPE, self)
    end
  end
end
