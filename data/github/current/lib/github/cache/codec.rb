# typed: true
# frozen_string_literal: true

require "msgpack"
require "date"
require "active_support/time_with_zone"
require "gitrpc/error"
require "github/diff/entry"

module GitHub
  module Cache
    class Codec
      INTEGER_MIN = -(2**63)
      INTEGER_MAX = 2**64 - 1

      # These are all the registered types for objects that are allowed
      # to be cached. Only ever add to this list, don't remove entries here.
      # If you find yourself wanting to add to this list, please first
      # reconsider to see if you can cache a basic type that is already
      # allowed instead. That would almost always be the better answer
      # rather than adding to this list.

      SYMBOL_TYPE         = 0x00
      DATE_TYPE           = 0x01
      DATE_TIME_TYPE      = 0x02
      BIG_DECIMAL_TYPE    = 0x03
      INTEGER_TYPE        = 0x04
      SET_TYPE            = 0x05
      TIME_WITH_ZONE_TYPE = 0x06
      SAFE_BUFFER_TYPE    = 0x07
      BIG_INTEGER_TYPE    = 0x08
      ENCODED_STRING_TYPE = 0x09

      # The existing entries below are long existing things that were
      # there from before MessagePack was used when arbitrary objects
      # were allowed to be cached with Marshal. So the existing ones
      # can be better considered either legacy we don't want to add to,
      # or more basic type we want to allow.

      GITRPC_TIMEOUT_TYPE           = 0x21
      DIFF_ENTRY_TYPE               = 0x22
      UNSULLIED_PAGE_DATA_HTML_TYPE = 0x23
      TASK_LIST_SUMMARY_TYPE        = 0x24
      MIGRATION_MAP_CONFLICT_TYPE   = 0x25

      def self.encode(key, value, flags)
        [pack(value), flags]
      end

      def self.decode(key, value, flags)
        unpack(value)
      end

      def self.pack(value)
        factory.pack(replace_value(value))
      end

      def self.unpack(value)
        factory.unpack(value)
      end

      def self.register_type(type, klass)
        packer = begin
          klass.const_get(:PACKER)
        rescue NameError => e
          raise ArgumentError, "class needs to have a PACKER constant defining the packing logic"
        end

        unpacker = begin
          klass.const_get(:UNPACKER)
        rescue NameError => e
          raise ArgumentError, "class needs to have a UNPACKER constant defining the unpacking logic"
        end

        factory.register_type(
          type,
          klass,
          packer: packer,
          unpacker: unpacker
        )
      end

      def self.factory
        @factory ||= MessagePack::Factory.new
      end

      # This replaces the value of the object we cache
      # since we need to wrap some specific types in
      # order to be able to cache them.
      def self.replace_value(value)
        case value
        when ActiveSupport::SafeBuffer
          GitHub::Cache::SafeBuffer.new(value)
        when String
          case value.encoding
          when ::Encoding::ASCII, ::Encoding::UTF_8, ::Encoding::BINARY
            value
          else
            GitHub::Cache::EncodedString.new(value)
          end
        when Integer
          if value < INTEGER_MIN || value > INTEGER_MAX
            GitHub::Cache::BigInteger.new(value)
          else
            value
          end
        when Array
          value.map do |val|
            replace_value(val)
          end
        when Set
          list = value.map do |val|
            replace_value(val)
          end
          Set.new(list)
        when Hash
          res = {}
          value.each do |key, val|
            res[key] = replace_value(val)
          end
          res
        else
          value
        end
      end
    end
  end
end

GitHub::Cache::Codec.factory.register_type(GitHub::Cache::Codec::SYMBOL_TYPE, Symbol)

GitHub::Cache::Codec.factory.register_type(
  MessagePack::Timestamp::TYPE,
  Time,
  packer: MessagePack::Time::Packer,
  unpacker: MessagePack::Time::Unpacker
)

GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::DATE_TYPE,
  Date,
  packer: lambda { |d| GitHub::Cache::Codec.factory.pack(d.to_time) },
  unpacker: lambda { |d| GitHub::Cache::Codec.factory.unpack(d).to_date },
)

GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::INTEGER_TYPE,
  Integer,
  packer: lambda { |d| GitHub::Cache::Codec.factory.pack(d.to_s) },
  unpacker: lambda { |d| GitHub::Cache::Codec.factory.unpack(d).to_i },
)

GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::DATE_TIME_TYPE,
  DateTime,
  packer: lambda { |d| GitHub::Cache::Codec.factory.pack(d.to_time) },
  unpacker: lambda { |d| GitHub::Cache::Codec.factory.unpack(d).to_datetime },
)

GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::BIG_DECIMAL_TYPE,
  BigDecimal,
  packer: lambda { |b| GitHub::Cache::Codec.factory.pack(b.to_s) },
  unpacker: lambda { |d| BigDecimal(GitHub::Cache::Codec.factory.unpack(d)) },
)

# There is no standard for Set, so add a custom
# handler here. Alternatively, Set usage
# could be removed.
GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::SET_TYPE,
  Set,
  packer: lambda { |s| GitHub::Cache::Codec.factory.pack(s.to_a) },
  unpacker: lambda { |d| Set.new(GitHub::Cache::Codec.factory.unpack(d)) }
)

# Packing / unpacking logic based in the ActiveSupport::TimeWithZone
# internal Marshal implementation.
GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::TIME_WITH_ZONE_TYPE,
  ActiveSupport::TimeWithZone,
  packer: lambda { |t| GitHub::Cache::Codec.factory.pack([t.utc, t.time_zone.name, t.time]) },
  unpacker: lambda do |d|
    utc, zone_name, time = GitHub::Cache::Codec.factory.unpack(d)
    ActiveSupport::TimeWithZone.new(utc.utc, ::Time.find_zone(zone_name), time.utc)
  end,
)

GitHub::Cache::Codec.factory.register_type(
  GitHub::Cache::Codec::GITRPC_TIMEOUT_TYPE,
  GitRPC::Timeout,
  packer: lambda { |t| GitHub::Cache::Codec.factory.pack([t.message, t.original, t.cached, t.argv]) },
  unpacker: lambda do |d|
    message, original, cached, argv = GitHub::Cache::Codec.factory.unpack(d)
    GitRPC::Timeout.new(message, original, cached: cached, argv: argv)
  end,
)

GitHub::Cache::Codec.register_type(GitHub::Cache::Codec::DIFF_ENTRY_TYPE, GitHub::Diff::Entry)
