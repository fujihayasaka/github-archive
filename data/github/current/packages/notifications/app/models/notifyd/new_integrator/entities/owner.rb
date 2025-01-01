# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator::Entities
  class Owner
    extend T::Sig
    extend T::Helpers

    class Types < T::Enum
      enums do
        User = new
        Organization = new
      end
    end

    sig { returns(Integer) }
    attr_reader :id

    sig { returns(Types) }
    attr_reader :type

    sig { params(id: Integer).returns(T.attached_class) }
    def self.new_user(id:)
      new(id: id, type: Types::User)
    end

    sig { params(id: Integer).returns(T.attached_class) }
    def self.new_organization(id:)
      new(id: id, type: Types::Organization)
    end

    sig { params(id: Integer, type: Types).void }
    def initialize(id:, type:)
      @id = id
      @type = type
    end

    sig { returns(T::Boolean) }
    def organization?
      type == Types::Organization
    end

    sig { returns(Symbol) }
    def to_symbol
      organization? ? :ORGANIZATION : :USER
    end
  end
end
