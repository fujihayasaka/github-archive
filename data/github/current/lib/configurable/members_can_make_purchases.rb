# typed: strict
# frozen_string_literal: true

module Configurable
  module MembersCanMakePurchases
    extend T::Sig
    extend T::Helpers

    KEY = "disable_members_can_make_purchases"

    requires_ancestor { ApplicationRecord::Base }

    sig { params(actor: User).void }
    def allow_members_can_make_purchases(actor:)
      raise ArgumentError, "members_can_make_purchases can only be configued on a Business" unless is_a?(Business)
      T.bind(self, Business)

      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_make_purchases.enable")
      GitHub.instrument(
          "members_can_make_purchases.enable",
          { user: actor, business: self })
    end

    sig { params(actor: User, force: T::Boolean).void }
    def disallow_members_can_make_purchases(actor:, force: false)
      raise ArgumentError, "members_can_make_purchases can only be configued on a Business" unless is_a?(Business)
      T.bind(self, Business)

      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_make_purchases.disable")
      GitHub.instrument(
          "members_can_make_purchases.disable",
          { user: actor, business: self })
    end

    sig { returns(T::Boolean) }
    def members_can_make_purchases?
      T.bind(self, Configurable)

      !config.enabled?(KEY)
    end
  end
end
