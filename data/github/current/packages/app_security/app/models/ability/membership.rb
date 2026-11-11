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

  private def push_org_id_context
    org_id = if is_a?(Organization)
      self.id
    elsif is_a?(Repository)
      self.organization_id
    else
      nil
    end
    Failbot.push("gh.organization.id": org_id)
    org_id
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
    org_id = push_org_id_context
    GitHub.dogstats.distribution_time("ability.membership.member_ids", tags: ["subject_type:#{ability_type}"]) do
      correlation_id = SecureRandom.urlsafe_base64(18)
      start_time = Time.current.utc
      member_ids = member_ids_processing(
        action:,
        actor_ids:,
        limit:,
        slice:,
        min_action:,
        include_indirect_abilities:,
        correlation_id:
      )
      GitHub.logger.info(
        "ability.membership.member_ids",
        "gh.organization.id": org_id,
        "gh.abilities.action": action,
        "gh.subject.type": ability_type,
        "gh.actor.ids.size": actor_ids&.size,
        "gh.abilities.limit": limit,
        "gh.abilities.slice": slice,
        "gh.abilities.min_action": min_action,
        "gh.abilities.include_indirect_abilities": include_indirect_abilities,
        "gh.correlation_id": correlation_id,
        "gh.backtrace": Rails.backtrace_cleaner.clean(caller[0..40]).join("\n").truncate(4000),
        "gh.duration_ms": (Time.current.utc - start_time) * 1000,
        "code.namespace": self.class.name,
        "code.function": __method__,
      )
      member_ids
    end
  end

  private def member_ids_processing(
    action: nil,
    actor_ids: nil,
    limit: nil,
    slice: BATCH_SIZE,
    min_action: nil,
    include_indirect_abilities: true,
    correlation_id: nil
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

          start_time = Time.current.utc
          direct_member_ids = direct_member_ability_scope(
            action: action,
            min_action: min_action
          ).pluck(:actor_id)
          member_list = (direct_member_ids & actor_ids.map(&:to_i))
          member_list = member_list.take(limit) if limit
          member_list = member_list.to_set
          GitHub.logger.info(
            "ability.membership.member_ids.direct_member_ids",
            "gh.abilities.use_indirect_abilities": use_indirect_abilities,
            "gh.correlation_id": correlation_id,
            "gh.duration_ms": (Time.current.utc - start_time) * 1000,
          )

          if use_indirect_abilities
            start_time = Time.current.utc
            member_list.merge(
              indirect_member_ids(
                action: action,
                actor_ids: actor_ids,
                min_action: min_action
              )
            )
            GitHub.logger.info(
              "ability.membership.member_ids.indirect_member_ids",
              "gh.correlation_id": correlation_id,
              "gh.duration_ms": (Time.current.utc - start_time) * 1000,
            )
          end
          member_list.to_a
        else
          start_time = Time.current.utc
          ids = direct_member_ability_scope(action: action, min_action: min_action).limit(limit).pluck(:actor_id)
          GitHub.logger.info(
            "ability.membership.member_ids.direct_member_ids",
            "gh.abilities.use_indirect_abilities": use_indirect_abilities,
            "gh.correlation_id": correlation_id,
            "gh.duration_ms": (Time.current.utc - start_time) * 1000,
          )

          if use_indirect_abilities
            start_time = Time.current.utc
            ids += indirect_member_ids(action: action, min_action: min_action)
            ids = ids.uniq
            GitHub.logger.info(
              "ability.membership.member_ids.indirect_member_ids",
              "gh.correlation_id": correlation_id,
              "gh.duration_ms": (Time.current.utc - start_time) * 1000,
            )
            ids
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
    org_id = push_org_id_context
    GitHub.dogstats.distribution_time("ability.membership.members_count") do
      correlation_id = SecureRandom.urlsafe_base64(18)
      start_time = Time.current.utc
      member_count = members_count_processing(
        action:,
        include_indirect_abilities:,
        correlation_id:
      )
      GitHub.logger.info(
        "ability.membership.members_count",
        "gh.organization.id": org_id,
        "gh.abilities.action": action,
        "gh.subject.type": ability_type,
        "gh.abilities.include_indirect_abilities": include_indirect_abilities,
        "gh.correlation_id": correlation_id,
        "gh.backtrace": Rails.backtrace_cleaner.clean(caller[0..40]).join("\n").truncate(4000),
        "gh.duration_ms": (Time.current.utc - start_time) * 1000,
        "code.namespace": self.class.name,
        "code.function": __method__,
      )
      member_count
    end
  end

  sig { params(action: T.nilable(Symbol), include_indirect_abilities: T::Boolean, correlation_id: T.nilable(String)).returns(Integer) }
  private def members_count_processing(action: nil, include_indirect_abilities: true, correlation_id: nil)
    return 0 if ability_id.nil?

    use_indirect_abilities = include_indirect_abilities && indirect_abilities_enabled?

    cache_key = ["members_count", ability_type, ability_id, action]
    cache_key << use_indirect_abilities if use_indirect_abilities

    PermissionCache.fetch(cache_key) do
      if use_indirect_abilities
        start_time = Time.current.utc
        indirect_ids = indirect_member_ids(action: action)
        count = indirect_ids.size
        GitHub.logger.info(
          "ability.membership.members_count.indirect_member_ids",
          "gh.correlation_id": correlation_id,
          "gh.duration_ms": (Time.current.utc - start_time) * 1000,
        )

        start_time = Time.current.utc
        if count == 0
          count = direct_member_ability_scope(action: action).count(:actor_id)
        else
          direct_member_ids = direct_member_ability_scope(action: action).pluck(:actor_id)
          count = (indirect_ids | direct_member_ids).size
        end
        GitHub.logger.info(
          "ability.membership.members_count.direct_member_ids",
          "gh.abilities.use_indirect_abilities": true,
          "gh.correlation_id": correlation_id,
          "gh.duration_ms": (Time.current.utc - start_time) * 1000,
        )
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
    return Promise.resolve(false) unless self.is_a?(Organization)
    return Promise.resolve(false) if id.nil?

    Orgs.domain.teams.async_business_team_ids_for_assigned_orgs(organization_id: id).then do |business_team_ids|
      GitHub.dogstats.distribution_time("ability.indirect_member.latency") do
        Platform::Loaders::UserBusinessTeamsCheck.load(
          user.ability_id,
          business_team_ids
        )
      end
    end
  end

  # Is user a direct member of this subject?
  def async_member?(user, include_indirect_abilities: true)
    return async_direct_member?(user) if !include_indirect_abilities
    return Promise.resolve(false) unless user.is_a?(User) && user.user?

    async_direct_member?(user).then do |is_direct_member|
      is_direct_member ? Promise.resolve(true) : async_indirect_member?(user)
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
