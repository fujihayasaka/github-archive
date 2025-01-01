# typed: strict
# frozen_string_literal: true

require "msgpack"

module FeatureFlag
  module Cache
    class MsgPack
      sig { returns(MessagePack::Factory) }
      def self.factory
        @factory ||= T.let(MessagePack::Factory.new, T.nilable(MessagePack::Factory))
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def self.pack(value)
        factory.pack(value)
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def self.unpack(value)
        factory.unpack(value)
      end
    end
  end
end

FeatureFlag::Cache::MsgPack.factory.register_type(0x00, Symbol)

FeatureFlag::Cache::MsgPack.factory.register_type(
  0x50,
  Vexi::FeatureFlag,
  packer: ->(obj) {
    FeatureFlag::Cache::MsgPack.pack(obj.to_hash)
  },
  unpacker: ->(data) {
    Vexi::FeatureFlag.from_hash(FeatureFlag::Cache::MsgPack.unpack(data))
  }
)

FeatureFlag::Cache::MsgPack.factory.register_type(
  0x51,
  Vexi::Segment,
  packer: ->(obj) {
    FeatureFlag::Cache::MsgPack.pack(obj.to_hash)
  },
  unpacker: ->(data) {
    Vexi::Segment.from_hash(FeatureFlag::Cache::MsgPack.unpack(data))
  }
)
