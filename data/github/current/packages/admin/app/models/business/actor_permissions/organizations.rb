# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::Organizations
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified actor transfer organizations out of this business?
  #
  # actor - User representing the actor.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_transfer_organizations?(actor)
    return false if GitHub.single_business_environment?
    return false if enterprise_managed_user_enabled?
    return false if spammy?
    return false if trial?

    actor.present? && owner?(actor)
  end

  # Public: Can the specified User remove Organizations from the Business?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_remove_organizations?(actor)
    return false if GitHub.single_business_environment? ||
      enterprise_managed_user_enabled? ||
      actor.blank?

    return true if owner?(actor)
    return false unless business.erp_feature_enabled?(:enterprise_fgps_org_administration)

    Authz.domain.check_allowed(actor, :remove_enterprise_organizations, business)
  end

  private

  sig { returns(Business) }
  def business
    T.cast(self, Business)
  end
end
