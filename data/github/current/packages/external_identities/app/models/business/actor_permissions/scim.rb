# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::SCIM
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user view enterprise SCIM settings?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_read_scim?(actor)
    return false if actor.blank?
    Authz.domain.check_allowed(actor, :read_enterprise_scim, business)
  end

  # Public: Can the specified user modify enterprise SCIM settings?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_write_scim?(actor)
    return false if actor.blank?
    Authz.domain.check_allowed(actor, :write_enterprise_scim, business)
  end
end
