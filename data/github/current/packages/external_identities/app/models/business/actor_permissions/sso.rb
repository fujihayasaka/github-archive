# typed: strict
# frozen_string_literal: true

module Business::ActorPermissions::Sso
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Can the specified user view enterprise single sign-on settings?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_read_sso?(actor)
    return false if actor.blank?
    Authz.domain.check_allowed(actor, :read_enterprise_sso, business)
  end

  # Public: Can the specified user modify enterprise single sign-on settings?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_write_sso?(actor)
    return false if actor.blank?
    Authz.domain.check_allowed(actor, :write_enterprise_sso, business)
  end


  # Public: Can the specified user view enterprise single sign-on or SCIM settings?
  #
  # actor - The User that is the actor to check.
  #
  # Returns Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def actor_can_read_sso_or_scim?(actor)
    return false if actor.blank?
    Authz.domain.check_multiple_permissions(actor, [:read_enterprise_sso, :read_enterprise_scim], business).values.any?
  end
end
