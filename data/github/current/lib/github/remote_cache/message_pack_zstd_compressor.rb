# typed: strict
# frozen_string_literal: true

require "msgpack"
require "zstd-ruby"

module GitHub
  module RemoteCache
    # Note: If you change this class, consider bumping the cache version
    # in `GitHub::RemoteCache::Store` (`CACHE_FORMAT_VERSION`).
    #
    # If the compression logic is changed, it may affect cache compatibility in that
    # existing cache values cannot be decompressed by the new logic.
    class MessagePackZstdCompressor
      extend GitHub::RemoteCache::Compressor

      COMPRESSION_THRESHOLD = T.let(1.kilobyte, Integer)
      MAX_ATTEMPT_CACHE_SIZE = T.let(10.megabytes, Integer)

      COMPRESSION_FLAG_COMPRESSED = T.let("\x01".freeze, String)
      COMPRESSION_FLAG_UNCOMPRESSED = T.let("\x00".freeze, String)

      # These are the registered types which aren't supported by default in
      # msgpack. Only ever add to this list, don't remove entries here.
      # If you find yourself wanting to add to this list, please first
      # reconsider to see if you can cache a basic type that is already
      # allowed instead. That would almost always be the better answer
      # rather than adding to this list.
      #
      # See these docs on msgpack extension types:
      # https://github.com/msgpack/msgpack/blob/master/spec.md#extension-types
      DATE_TYPE = 0x00

      class CacheValueTooLargeForCompressionError < StandardError; end
      class CacheValueTooSmallForDecompressionError < StandardError; end

      sig { override.params(value: T.untyped).returns(String) }
      def self.compress(value)
        # Always serialize with MessagePack first
        msgpack_data = pack(value)

        raise CacheValueTooLargeForCompressionError.new if msgpack_data.bytesize > MAX_ATTEMPT_CACHE_SIZE

        if msgpack_data.bytesize > COMPRESSION_THRESHOLD
          compressed_data = Zstd.compress(msgpack_data)
          COMPRESSION_FLAG_COMPRESSED + compressed_data
        else
          COMPRESSION_FLAG_UNCOMPRESSED + msgpack_data
        end
      end

      sig { override.params(raw_value: String).returns(T.untyped) }
      def self.decompress(raw_value)
        # Expect at least 2 bytes: compression flag + some data
        raise CacheValueTooSmallForDecompressionError.new if raw_value.bytesize <= 1

        # We already checked that there are at least 2 bytes, so these can't be nil and we
        # can safely use T.must here.
        compression_flag_byte = T.must(raw_value.getbyte(0))
        data = T.must(raw_value.byteslice(1..-1))

        if compression_flag_byte == COMPRESSION_FLAG_COMPRESSED.getbyte(0)
          decompressed_data = Zstd.decompress(data)
          unpack(decompressed_data)
        elsif compression_flag_byte == COMPRESSION_FLAG_UNCOMPRESSED.getbyte(0)
          unpack(data)
        end
      end

      sig { params(value: T.untyped).returns(String) }
      def self.pack(value)
        factory.pack(value)
      end

      sig { params(value: String).returns(T.untyped) }
      def self.unpack(value)
        factory.unpack(value)
      end

      sig { returns(MessagePack::Factory) }
      def self.factory
        @factory
      end

      @factory = T.let(MessagePack::Factory.new, MessagePack::Factory)

      @factory.register_type(
        MessagePack::Timestamp::TYPE,
        Time,
        packer: MessagePack::Time::Packer,
        unpacker: MessagePack::Time::Unpacker
      )

      @factory.register_type(
        GitHub::RemoteCache::MessagePackZstdCompressor::DATE_TYPE,
        Date,
        packer: lambda { |date| GitHub::RemoteCache::MessagePackZstdCompressor.factory.pack(date.to_time) },
        unpacker: lambda { |date| GitHub::RemoteCache::MessagePackZstdCompressor.factory.unpack(date).to_date }
      )
    end
  end
end
