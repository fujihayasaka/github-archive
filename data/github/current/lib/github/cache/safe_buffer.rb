# typed: false
# frozen_string_literal: true

module GitHub
  module Cache

    # So why does this class exist? Well, msgpack ends up
    # packing an ActiveSupport::SafeBuffer always a String,
    # losing the html safe state. We can't solve this with
    # a custom type wrapper, because internally msgpack
    # always treats any subtype of String as String.
    #
    # So we have this wrapper class that allows us to
    # serialize and deserialize without losing the
    # html safe state.
    class SafeBuffer
      def initialize(buf)
        @buf = buf
      end

      def to_str
        @buf
      end

      def to_s
        to_str
      end

      PACKER = lambda do |obj|
        buf = obj.to_str
        GitHub::Cache::Codec.factory.pack([buf, buf.html_safe?])
      end

      UNPACKER = lambda do |data|
        str, safe = GitHub::Cache::Codec.factory.unpack(data)
        if safe
          ActiveSupport::SafeBuffer.new(str)
        else
          str
        end
      end

      GitHub::Cache::Codec.register_type(GitHub::Cache::Codec::SAFE_BUFFER_TYPE, self)
    end
  end
end
