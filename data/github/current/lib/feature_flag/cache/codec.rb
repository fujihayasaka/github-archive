# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    class Codec
      sig { params(key: T.untyped, value: T.untyped, flags: T.untyped).returns(T::Array[T.untyped]) }
      def self.encode(key, value, flags)
        [MsgPack.pack(value), flags]
      end

      sig { params(key: T.untyped, value: T.untyped, flags: T.untyped).returns(T.untyped) }
      def self.decode(key, value, flags)
        MsgPack.unpack(value)
      end
    end
  end
end
