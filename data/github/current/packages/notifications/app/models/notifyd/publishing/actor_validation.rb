# typed: true
# frozen_string_literal: true

module Notifyd::Publishing
  class ActorValidation
    extend T::Sig

    attr_reader :actor, :status, :reason

    sig { params(actor: T.nilable(User)).void }
    def initialize(actor:)
      @actor = actor
      @status = :invalid
      @reason = "none"
    end

    sig { returns(ActorValidation) }
    def validate
      if actor.blank?
        invalid!
        @reason = "nil"
        return self
      end

      if actor.spammy? || actor.suspended?
        invalid!
        @reason = actor.spammy? ? "spammy" : "suspended"
        return self
      end

      valid!
      self
    end

    sig { returns(T::Boolean) }
    def valid?
      @status == :valid
    end

    sig { returns(T::Boolean) }
    def invalid?
      !valid?
    end

    private

    def invalid!
      @status = :invalid
    end

    def valid!
      @status = :valid
    end
  end
end
