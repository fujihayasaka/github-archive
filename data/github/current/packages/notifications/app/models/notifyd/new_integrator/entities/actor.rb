# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Actor
    extend T::Sig
    include Notifyd::NewIntegrator::Serializable

    sig { returns(Integer) }
    attr_reader :id

    sig { returns(String) }
    attr_reader :display_login

    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(T.attached_class) }
    def self.from_h(hash)
      self.new(
        id: T.let(hash[:id], Integer),
        display_login: T.let(hash[:display_login], String),
      )
    end

    sig { params(id: Integer, display_login: String).void }
    def initialize(id:, display_login:)
      @id = id
      @display_login = display_login
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def as_serializable
      {
        id: id,
        display_login: display_login
      }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      Notifyd::NewIntegrator::Serializer.serialize(self)
    end
  end
end
