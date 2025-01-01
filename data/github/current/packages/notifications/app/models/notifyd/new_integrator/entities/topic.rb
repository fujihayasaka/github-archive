# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Topic
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(String) }
    attr_reader :type

    sig { returns(String) }
    attr_reader :value

    sig { params(type: String, value: String).void }
    def initialize(type:, value:)
      @type = type
      @value = value
    end

    sig { override.returns(T::Hash[Symbol, String]) }
    def as_serializable
      { type: type, value: value }
    end

    sig { returns(T::Hash[Symbol, String]) }
    def to_h
      Notifyd::NewIntegrator::Serializer.serialize(self)
    end
  end
end
