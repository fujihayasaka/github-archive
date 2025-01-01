# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Attribute
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :value

    sig { params(name: String, value: String).void }
    def initialize(name:, value:)
      @name = name
      @value = value
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def as_serializable
      { name: name, value: value }
    end

    sig { returns(T::Hash[Symbol, String]) }
    def to_h
      Notifyd::NewIntegrator::Serializer.serialize(self)
    end
  end
end
