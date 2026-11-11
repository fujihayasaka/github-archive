# typed: true
# frozen_string_literal: true

module Business::SupportEntitleeDependency
  extend T::Helpers
  requires_ancestor { Business }

  MAXIMUM_PREMIUM_SUPPORT_ENTITLEES = 20
  MAXIMUM_PREMIUM_PLUS_SUPPORT_ENTITLEES = 40

  # Public: Add a support entitlement for a user in the business
  #
  # A Business::SupportEntitlee is a User who is a member of a
  # Business and is entitled to view/open tickets for the Business
  # in the HelpHub support portal
  #
  # user        - The User to add the support entitlement for
  # actor       - The User adding the support entitlement
  #
  # Does nothing if the user is not a member of the business.
  #
  # Returns nothing.
  def add_support_entitlee(user, actor:)
    return unless member?(user)
    return if actor_ids(type: "SupportEntitlee").count >= max_support_entitlees

    grant Business::SupportEntitlee.new(user), :write
    instrument :add_support_entitlee, user: user, actor: actor
  end

  # Public: Remove a support entitlement for a user in the business
  #
  # user    -  The User to remove the support entitlment for
  # actor   - The User revoking the support entitlement
  #
  # Returns nothing.
  def remove_support_entitlee(user, actor:)
    with_write { revoke Business::SupportEntitlee.new(user) }
    instrument :remove_support_entitlee, user: user, actor: actor
  end

  # Internal: remove support entitlees
  #
  # users: - specified users in the business
  #
  def remove_support_entitlees(users:)
    users.select { |user| user.id.in?(support_entitled_actor_ids) }.each do |user|
      remove_support_entitlee(user, actor: nil)
    end
  end

  # Internal: remove all support entitlees
  def remove_all_support_entitlees
    remove_support_entitlees(users: User.where(id: support_entitled_actor_ids, type: "User"))
  end

  # Internal: support entitled actor ids direct from abilities
  def support_entitled_actor_ids
    @support_entitled_actor_ids ||= actor_ids(type: "SupportEntitlee")
  end

  # Public: Does the given user have a support entitlement for this Business?
  #
  # user - The user to check.
  #
  # Returns a Boolean.
  def support_entitled?(user)
    member?(user) && permit?(Business::SupportEntitlee.new(user), :write)
  end

  # Public: The users with a support entitlement for this Business
  #
  # Returns ActiveRecord::Relation of User
  def support_entitlees
    entitled_actor_ids = actor_ids(type: "SupportEntitlee")
    entitled_members = User.where(id: entitled_actor_ids).select { |u| member?(u) }.map(&:id)
    User.where(id: entitled_members, type: "User")
  end

  # Public: The maximum number of support entitlees allowed for this business
  #
  # Returns an integer
  def max_support_entitlees
    return MAXIMUM_PREMIUM_PLUS_SUPPORT_ENTITLEES if has_premium_plus_support_plan?

    MAXIMUM_PREMIUM_SUPPORT_ENTITLEES
  end
end
