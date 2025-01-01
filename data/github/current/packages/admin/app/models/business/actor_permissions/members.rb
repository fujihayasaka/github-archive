# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::Members
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user view enterprise members and other non-admin roles?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_read_members?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check

    Authz.domain.check_allowed(actor, :read_enterprise_members, business)
  end

  # Public: Can the specified user add, invite, and remove enterprise members and other non-admin roles?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_manage_members?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check

    Authz.domain.check_allowed(actor, :manage_enterprise_members, business)
  end

  # Public: Can the specified user view enterprise admins?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_read_admins?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check

    Authz.domain.check_allowed(actor, :read_enterprise_admins, business)
  end

  # Public: Can the specified user add, invite, and remove enterprise administrators?
  #
  # actor - The User that is the actor to check.
  # skip_owner_check - Boolean to bypass owner check. Used if the caller has already checked for owner.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User), skip_owner_check: T::Boolean).returns(T::Boolean) }
  def actor_can_manage_admins?(actor, skip_owner_check: false)
    return false if actor.blank?
    return true if owner?(actor) unless skip_owner_check

    Authz.domain.check_allowed(actor, :manage_enterprise_admins, business)
  end

  private

  sig { returns(Business) }
  def business
    T.cast(self, Business)
  end
end
