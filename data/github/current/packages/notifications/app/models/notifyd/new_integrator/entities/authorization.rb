# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Authorization
    SKIP = { skip_enforcement: true }

    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :saml_enforcement

    sig { returns(T::Array[T.untyped]) }
    attr_reader :authzd_attributes

    sig { params(owner: Owner, authzd_attributes: T::Array[T.untyped]).void }
    def initialize(owner:, authzd_attributes:)
      @authzd_attributes = authzd_attributes
      @saml_enforcement = owner.organization? ? { organization_id: owner.id } : SKIP
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def as_serializable
      {
        authzd_attributes: authzd_attributes.map { |a| any(a) },
        saml_enforcement: saml_enforcement,
      }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      Notifyd::NewIntegrator::Serializer.serialize(self)
    end

    private

    def any(data)
      Notifyd::NewIntegrator::Serializers::ProtobufAny.new(data)
    end
  end
end
