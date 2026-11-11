# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::EnterpriseTeams
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user create new enterprise teams?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_create_enterprise_teams?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check
    return false unless business.erp_feature_enabled?(:enterprise_teams_fgps)

    Authz.domain.check_allowed(actor, :create_enterprise_teams, business)
  end

  private

  sig { returns(Business) }
  def business
    T.cast(self, Business)
  end
end
