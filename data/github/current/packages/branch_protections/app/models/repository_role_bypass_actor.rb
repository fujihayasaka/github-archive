# typed: true
# frozen_string_literal: true

class RepositoryRoleBypassActor < RepositoryRulesetBypassActor
  validate :ensure_actor
  validate :ensure_valid_role

  ADMIN_NAME = "Repository admin"

  def self.display_type
    "RepositoryRole"
  end

  def self.display_name
    "Repository roles"
  end

  sig { returns(T.nilable(RepositoryRole)) }
  def role
    T.let(actor, T.nilable(RepositoryRole))
  end

  def ensure_actor
    errors.add(:base, "actor_id is required for RepositoryRole") if actor_id.nil?
    errors.add(:actor, "must be a RepositoryRole") unless actor_type == "RepositoryRole"
  end

  def ensure_valid_role
    return if @validated_associations
    return if actor.nil?
    unless actor.is_a?(RepositoryRole)
      errors.add("actor", "must be a RepositoryRole")
      return
    end

    if actor.owner_id.present?
      # custom role
      if ruleset_organization.present?
        custom_roles = RepositoryRole.custom_roles_for_org(ruleset_organization).where(id: actor_id).index_by(&:id)
      end
      unless custom_roles.key?(actor_id)
        errors.add("actor", "role must be part of the ruleset source or owner organization")
      end
    else
      # default role
      default_role = RepositoryRole.find_by(owner_id: nil, id: actor_id)
      unless ALLOWED_BASE_ROLES.include?(default_role&.name)
        errors.add("actor", "base role does not have write permissions")
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def actor_name
    self.role&.name == "admin" ? ADMIN_NAME : role&.name&.humanize
  end

  sig { returns(String) }
  def actor_display_type
    self.class.display_type
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String)
    )
    .returns(T::Array[RepositoryRoleBypassActor])
  end
  def self.suggest_bypassers(source, query)
    get_base_roles(query) + get_custom_roles(source, query)
  end

  sig do
    params(query: T.nilable(String))
    .returns(T::Array[RepositoryRoleBypassActor])
  end
  private_class_method def self.get_base_roles(query)
    @cached_base_roles ||= T.let(RepositoryRole.where(owner_id: nil, name: RepositoryRulesetBypassActor::ALLOWED_BASE_ROLES), T.untyped)

    bypass_actors = []
    @cached_base_roles.each do |role|
      if query.present?
        name = role.name == "admin" ? ADMIN_NAME : role.name
        next unless name.downcase.include?(query)
      end
      bypass_actors << RepositoryRoleBypassActor.new(actor: role)
    end
    bypass_actors
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String)
    )
    .returns(T::Array[RepositoryRoleBypassActor])
  end
  private_class_method def self.get_custom_roles(source, query)
    if source.is_a?(Organization)
      corresponding_org = source
    else
      org_owner = Repository.where(id: source[:id]).org_owned.pluck(:owner_id)
      if org_owner
        corresponding_org = Organization.where(id: org_owner[0])[0]
      else
        []
      end
    end

    bypass_actors = []
    RepositoryRole.custom_roles_for_org(corresponding_org).each do |role|
      next if query.present? && !role.name.downcase.include?(query)
      bypass_actors << RepositoryRoleBypassActor.new(actor: role)
    end
    bypass_actors
  end

  sig do
    params(
      bypassers: T::Array[RepositoryRoleBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    repository = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository)
    return [] unless repository.is_a?(Repository)

    allowed_modes = []

    user = actor.is_a?(User) ? actor : actor.owner

    builtin_role_bypasses, custom_role_bypasses = bypassers.partition { |bypass| Team::ABILITIES_TO_PERMISSIONS.has_key?(bypass.actor&.name) }

    # Built-in roles use this hash to implement inheritance
    if builtin_role_bypasses.any?
      writeable_key =
        actor.is_a?(PublicKey) &&
        actor.respond_to?(:read_only?) &&
        !actor.read_only? &&
        actor.repository == repository

      user_roles = repository.permissions_hash_for(actor: user)

      builtin_role_bypasses.each do |bypass|
        # Allow bypass if the user has the role or is a write deploy key
        if user_roles[Team::ABILITIES_TO_PERMISSIONS[bypass.actor&.name].to_sym] ||
           (writeable_key && bypass.actor.target_type == "Repository")
          allowed_modes << bypass.bypass_mode
        end
      end
    end

    # Custom roles need to use a DB query
    if custom_role_bypasses.any? && repository.in_organization?
      role_ids = custom_role_bypasses.map(&:actor_id)
      query = UserRole.where(role_id: role_ids, target_type: "Repository", target_id: repository.id)
      if repository.business&.erp_feature_enabled?(:enterprise_teams_org_roles)
        matches = query
          .where(actor_type: %w[Team BusinessTeam], actor_id: user.teams(with_business_teams: true).pluck(:id)) # Custom role assigned to team user is member of
          .or(query.where(actor_type: "User", actor_id: user.id))     # Custom role assigned to user
      else
        matches = query
          .where(actor_type: "Team", actor_id: user.teams.pluck(:id)) # Custom role assigned to team user is member of
          .or(query.where(actor_type: "User", actor_id: user.id))     # Custom role assigned to user
      end

      matches.each do |match|
        custom_role_bypasses.find { |bypass| bypass.actor_id == match.role_id }.tap do |bypass|
          allowed_modes << bypass.bypass_mode if bypass
        end
      end
    end
    allowed_modes
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.bypassable_user_ids(repository, bypass_actors)
    custom_roles = T.let([], T::Array[RepositoryRole])
    system_roles = T.let([], T::Array[RepositoryRole])
    user_ids = []

    bypass_actors.each do |bypass_actor|
      next unless bypass_actor.actor
      if ALLOWED_BASE_ROLES.include?(bypass_actor.actor.name)
        system_roles.push(bypass_actor.actor)
      else
        custom_roles.push(bypass_actor.actor)
      end
    end

    if custom_roles.any?
      user_ids.push(*UserRole.where(actor_type: "User", target: repository, role_id: custom_roles).pluck(:actor_id))

      if repository.business&.erp_feature_enabled?(:enterprise_teams_org_roles)
        team_ids = UserRole.where(actor_type: %w[Team BusinessTeam], target: repository, role_id: custom_roles).pluck(:actor_id)
        user_ids |= Team.member_ids_indexed_by_team_ids(team_ids, immediate_only: false, with_business_teams: true).values.flatten.uniq
      else
        team_ids = UserRole.where(actor_type: "Team", target: repository, role_id: custom_roles).pluck(:actor_id)
        user_ids.push(*Team.member_ids_of(team_ids, immediate_only: false)) if team_ids.any?
      end
    end

    if system_roles.any?
      # Find minimum allowed action based on ranking
      min_action = T.must(system_roles.sort_by(&:action_rank).first).name

      ##
      # user_ids_with_privileged_access only accepts read, write, or admin. We fallback to write for other roles
      # supported in ruleset bypasses as these are commonly based on the write role.
      #
      min_action = "write" unless min_action == "write" || min_action == "admin"

      eligible_user_ids = repository.user_ids_with_privileged_access(min_action: min_action.to_sym) - user_ids
      eligible_users = User.batched_scope(:id, values: eligible_user_ids).to_a.index_by(&:id)

      _, user_to_highest_role_mapping = repository.batch_action_and_role_level_for(eligible_users.values)

      user_to_highest_role_mapping.each do |user_id, role|
        user = eligible_users[user_id]
        permissions = Repository.permissions_hash(role)

        system_roles.each do |system_role|
          next unless permissions[Team::ABILITIES_TO_PERMISSIONS[system_role.name].to_sym]

          user_ids.push(user_id)
          break
        end
      end
    end
    user_ids
  end
end
