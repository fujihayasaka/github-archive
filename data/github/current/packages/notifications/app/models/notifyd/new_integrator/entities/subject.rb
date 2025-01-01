# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Subject
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(String) }
    attr_reader :type

    sig { returns(Integer) }
    attr_reader :id

    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(T.attached_class) }
    def self.from_h(hash)
      new(
        type: T.let(hash[:type], String),
        id: T.let(hash[:id], Integer),
      )
    end

    sig { params(type: String, id: Integer).void }
    def initialize(type:, id:)
      @type = type
      @id = id
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        id: id,
        type: type
      }
    end

    sig { override.returns(T::Hash[Symbol, String]) }
    def as_serializable
      {
        value: id.to_s,
        type: type,
      }
    end
  end
end
