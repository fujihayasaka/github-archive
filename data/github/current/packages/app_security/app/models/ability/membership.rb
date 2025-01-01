# typed: true
# frozen_string_literal: true

# Combine this mixin with Ability::Subject to support User membership.
module Ability::Membership
  extend T::Helpers

  BATCH_SIZE = 5000

  requires_ancestor { Ability::Subject }
  requires_ancestor { Kernel }

  # A scope for Users who explicitly belong to this subject.
  #
  # action: - optional Symbol action (:read, :write, :admin) to limit actions
  # actor_ids: - optional Array filter to limit the user_ids we check
  def members(action: nil, actor_ids: nil, limit: nil, include_indirect_abilities: true)
    user_ids = member_ids(
      action: action,
      actor_ids: actor_ids,
      limit: limit,
      include_indirect_abilities: include_indirect_abilities
    )
    User.where(id: user_ids)
  end

  # limit: optional Sets a LIMIT to the Query
  # slice: optional Is used to set a limit on the number of actor_ids in the IN statement of the Query
  # include_indirect_abilities: optional whether to include indirect abilities (from BusinessTeam memberships) in the result
  def member_ids(
    action: nil,
    actor_ids: nil,
    limit: nil,
    slice: BATCH_SIZE,
    min_action: nil,
    include_indirect_abilities: true
  )
    return [] if ability_id.nil?

    use_indirect_abilities = include_indirect_abilities && indirect_abilities_enabled?

    cache_key = ["member_ids", ability_type, ability_id, action, actor_ids, limit, min_action]
    cache_key << use_indirect_abilities if use_indirect_abilities

    PermissionCache.fetch(cache_key) do
      ActiveRecord::Base.connected_to(role: :reading) do
        if actor_ids
          if !actor_ids.is_a?(Array)
            actor_ids = [actor_ids]
          end

          member_list = Set.new
          actor_ids.each_slice(slice) do |actor_slice|
            member_list.merge(
              direct_member_ability_scope(
                action: action,
                actor_ids: actor_slice,
                min_action: min_action
              ).limit(limit).pluck(:actor_id)
            )
          end
          if use_indirect_abilities
            member_list.merge(
              indirect_member_ids(
                action: action,
                actor_ids: actor_ids,
                min_action: min_action
              )
            )
          end
          member_list.to_a
        else
          ids = direct_member_ability_scope(action: action, min_action: min_action).limit(limit).pluck(:actor_id)
          if use_indirect_abilities
            ids += indirect_member_ids(action: action, min_action: min_action)
            ids.uniq
          else
            ids
          end
        end
      end
    end
  rescue Timeout::Error, Faraday::Error => e
    Failbot.push failbot_context
    raise e
  end

  # Whether to include indirect abilities (from BusinessTeam memberships) in the membership results.
  # If true, #indirect_member_ids must be implemented and will be used to fetch the indirect members.
  sig { overridable.returns(T::Boolean) }
  def indirect_abilities_enabled?
    false
  end

  sig do
    overridable.params(
      business_team_ids: T.nilable(T::Array[Integer]),
      action: T.nilable(T.any(String, Symbol)),
      actor_ids: T.nilable(T.any(Integer, T::Array[Integer])),
      limit: T.nilable(Integer),
      slice: Integer,
      min_action: T.nilable(T.any(String, Symbol))
    ).returns(T::Array[Integer])
  end
  def indirect_member_ids(business_team_ids: nil, action: nil, actor_ids: nil, limit: nil, slice: BATCH_SIZE, min_action: nil)
    raise NotImplementedError, "indirect_member_ids must be implemented when indirect_abilities_enabled? is true"
  end

  sig { params(action: T.nilable(Symbol), include_indirect_abilities: T::Boolean).returns(Integer) }
  def members_count(action: nil, include_indirect_abilities: true)
    return 0 if ability_id.nil?

    use_indirect_abilities = include_indirect_abilities && indirect_abilities_enabled?

    cache_key = ["members_count", ability_type, ability_id, action]
    cache_key << use_indirect_abilities if use_indirect_abilities

    PermissionCache.fetch(cache_key) do
      if use_indirect_abilities
        indirect_ids = indirect_member_ids(action: action)
        count = indirect_ids.size
        direct_member_ability_scope(action: action).find_in_batches(batch_size: BATCH_SIZE) do |batch|
          # members can have indirect abilities and direct abilities, so we need to get the unique ID count.
          count += (batch.pluck(:actor_id) - indirect_ids).size
        end
        count
      else
        direct_member_ability_scope(action: action).count(:actor_id)
      end
    end
  end

  # Is user a direct member of this subject?
  def member?(user, include_indirect_abilities: true)
    async_member?(user, include_indirect_abilities:).sync
  end

  # Is user a direct member of this subject?
  def async_direct_member?(user)
    return Promise.resolve(false) unless user.is_a?(User) && user.user?
    Platform::Loaders::AbilityMembershipCheck.load(self.ability_type, self.ability_id, user.ability_type, user.ability_id)
  end

  # Is user a indirect member of this subject?
  def async_indirect_member?(user)
    return Promise.resolve(false) unless indirect_abilities_enabled?
    return Promise.resolve(false) unless user.is_a?(User) && user.user?
    return Promise.resolve(false) if business_team_ids.empty?

    GitHub.dogstats.distribution_time("ability.indirect_member.latency") do
      Platform::Loaders::UserBusinessTeamsCheck.load(
        user.ability_id,
        business_team_ids
      )
    end
  end

  # Is user a direct member of this subject?
  def async_member?(user, include_indirect_abilities: true)
    return async_direct_member?(user) if !include_indirect_abilities
    return Promise.resolve(false) unless user.is_a?(User) && user.user?
    Promise.all([async_direct_member?(user), async_indirect_member?(user)]).then do |direct_member, indirect_member|
      direct_member || indirect_member
    end
  end

  def failbot_context
    { app: "roles_and_permissions" }
  end

  private def direct_member_ability_scope(action: nil, actor_ids: nil, min_action: nil)
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

  # Returns business team IDs enabled for this org
  private def business_team_ids
    return [] unless self.is_a?(Organization) && business.present?

    @business_team_ids ||= Orgs.domain.teams.business_team_ids_for_assigned_orgs(organization_id: id)
  end

end
