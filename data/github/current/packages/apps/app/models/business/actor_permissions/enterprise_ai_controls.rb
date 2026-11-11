# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::EnterpriseAiControls
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user read enterprise AI controls?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_read_enterprise_ai_controls?(actor)
    actor_can_access_enterprise_ai_controls?(actor, :read_enterprise_ai_controls)
  end

  # Public: Can the specified user manage enterprise AI controls?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_write_enterprise_ai_controls?(actor)
    actor_can_access_enterprise_ai_controls?(actor, :write_enterprise_ai_controls)
  end

  private

  # Private: Common logic for checking enterprise AI controls permissions
  #
  # actor - The User that is the actor to check.
  # permission - The Symbol permission to check (e.g., :read_enterprise_ai_controls, :write_enterprise_ai_controls).
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), permission: Symbol).returns(T::Boolean) }
  def actor_can_access_enterprise_ai_controls?(actor, permission)
    return false if actor.blank?

    # Check FGP if feature flag is enabled
    if FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, business, default: false)
      return Authz.domain.check_allowed(actor, permission, business)
    end

    # Fallback to admin check
    # TODO: Remove this fallback check when graduating the :enterprise_ai_controls_fine_grained_permissions feature flag.
    # This will reduce EXPECTED_COUNT in BusinessAdminAbilityChecksTest.
    business.adminable_by?(actor)
  end

  sig { returns(Business) }
  def business
    T.cast(self, Business)
  end
end
