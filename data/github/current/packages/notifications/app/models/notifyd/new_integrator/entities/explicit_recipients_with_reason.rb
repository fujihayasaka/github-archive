# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class ExplicitRecipientsWithReason
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(String) }
    attr_reader :reason

    sig { returns(T::Array[Integer]) }
    attr_reader :recipient_ids

    sig { params(reason: String, recipient_ids: T::Array[Integer]).void }
    def initialize(reason:, recipient_ids:)
      @reason = reason
      @recipient_ids = recipient_ids
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def as_serializable
      { reason: reason, user_ids: recipient_ids }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      Notifyd::NewIntegrator::Serializer.serialize(self)
    end
  end
end
