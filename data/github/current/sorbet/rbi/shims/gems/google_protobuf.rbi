# typed: true
# frozen_string_literal: true

# Tapioca's Protobuf DSL compiler emits per-message RBIs that subclass
# `Google::Protobuf::AbstractMessage`. That parent class doesn't exist at
# runtime; it's a synthetic anchor we declare here so every generated
# message picks up the C-extension class methods (`encode`, `decode`,
# `encode_json`, `decode_json`) without each per-message RBI having to
# repeat them.
module Google
  module Protobuf
    class AbstractMessage
      class << self
        sig { params(proto: String).returns(T.attached_class) }
        def decode(proto); end

        sig do
          params(
            json: String,
            options: T::Hash[Symbol, T.untyped],
          ).returns(T.attached_class)
        end
        def decode_json(json, options = {}); end

        sig { params(msg: Google::Protobuf::AbstractMessage).returns(String) }
        def encode(msg); end

        sig do
          params(
            msg: Google::Protobuf::AbstractMessage,
            options: T::Hash[Symbol, T.untyped],
          ).returns(String)
        end
        def encode_json(msg, options = {}); end

        sig { returns(::Google::Protobuf::Descriptor) }
        def descriptor; end
      end

      sig { returns(String) }
      def to_proto; end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
      def to_json(options = {}); end
    end
  end
end
