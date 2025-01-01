# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::Invitations
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user view enterprise invitations?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_read_invitations?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check
    return false unless business.erp_feature_enabled?(:enterprise_fgp_administration)

    Authz.domain.check_allowed(actor, :read_enterprise_members, business)
  end

  # Public: Can the specified user view enterprise invitations?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_read_admin_invitations?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if !skip_owner_check && owner?(actor)
    return false unless business.erp_feature_enabled?(:enterprise_fgp_administration)

    Authz.domain.check_allowed(actor, :read_enterprise_admins, business)
  end

  # Public: Can the specified user create or cancel user invitations?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_manage_invitations?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check
    return false unless business.erp_feature_enabled?(:enterprise_fgp_administration)

    Authz.domain.check_allowed(actor, :manage_enterprise_members, business)
  end

  # Public: Can the specified user create or cancel admin invitations?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_manage_admin_invitations?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if !skip_owner_check && owner?(actor)
    return false unless business.erp_feature_enabled?(:enterprise_fgp_administration)

    Authz.domain.check_allowed(actor, :manage_enterprise_admins, business)
  end

  private

  sig { returns(Business) }
  def business
    T.cast(self, Business)
  end
end
