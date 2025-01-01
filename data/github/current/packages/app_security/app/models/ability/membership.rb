# typed: false
# frozen_string_literal: true

# Combine this mixin with Ability::Subject to support User membership.
module Ability::Membership

  include Scientist

  # A scope for Users who explicitly belong to this subject.
  #
  # action: - optional Symbol action (:read, :write, :admin) to limit actions
  # actor_ids: - optional Array filter to limit the user_ids we check
  def members(action: nil, actor_ids: nil, limit: nil)
    user_ids = member_ids(action: action, actor_ids: actor_ids, limit: limit)
    User.where(id: user_ids)
  end

  # limit: optional Sets a LIMIT to the Query
  # slice: optional Is used to set a limit on the number of actor_ids in the IN statement of the Query
  def member_ids(action: nil, actor_ids: nil, limit: nil, slice: 5000, min_action: nil)
    return [] if ability_id.nil?

    PermissionCache.fetch ["member_ids", ability_type, ability_id, action, actor_ids, limit, min_action] do
      ActiveRecord::Base.connected_to(role: :reading) do

        if actor_ids
          if !actor_ids.is_a?(Array)
            actor_ids = [actor_ids]
          end

          member_list = []
          actor_ids.each_slice(slice) do |actor_slice|
            member_list = member_list | member_ability_scope(action: action, actor_ids: actor_slice, min_action: min_action).limit(limit).pluck(:actor_id)
          end
          member_list
        else
          member_ability_scope(action: action, min_action: min_action).limit(limit).pluck(:actor_id)
        end
      end
    end
  end

  def member_ability_scope(action: nil, actor_ids: nil, min_action: nil)
    scope = Ability.where(
      subject_id: ability_id,
      subject_type: ability_type,
      actor_type: "User",
      priority: Ability.priorities[:direct]
    )

    if action.present?
      scope = scope.where(action: Ability.actions[action])
    end

    if min_action.present?
      raise ArgumentError, "'#{min_action}' is not a valid value for min_action" unless Ability.actions.key?(min_action)
      scope = scope.where("action >= ?", Ability.actions[min_action])
    end

    if actor_ids
      scope = scope.where(actor_id: actor_ids)
    end

    scope.distinct
  end

  def members_count(action: nil)
    return 0 if ability_id.nil?

    PermissionCache.fetch ["members_count", ability_type, ability_id, action] do
      member_ability_scope(action: action).count(:actor_id)
    end
  end

  # Is user a direct member of this subject?
  def member?(user)
    # Enforce user.user? here rather than in the database query above
    # since during user-org transformation, the database has Organization as a
    # user's type before the user is revoked from teams it's a member of.
    async_member?(user).sync
  end

  def async_member?(user)
    return Promise.resolve(false) unless user.is_a?(User) && user.user?
    Platform::Loaders::AbilityMembershipCheck.load(self.ability_type, self.ability_id, user.ability_type, user.ability_id)
  end
end
