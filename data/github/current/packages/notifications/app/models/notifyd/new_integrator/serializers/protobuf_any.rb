# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Serializers
  class ProtobufAny
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(T.untyped) }
    attr_reader :data

    sig { params(data: T.untyped).void }
    def initialize(data)
      @data = data
    end

    sig { override.returns(Google::Protobuf::Any) }
    def as_serializable
      Google::Protobuf::Any.new.tap { |any| any.pack(data) }
    end
  end
end
