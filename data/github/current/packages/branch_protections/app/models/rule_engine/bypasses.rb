# typed: true
# frozen_string_literal: true

module RuleEngine
  module Bypasses
    extend T::Sig
    include Kernel
    include Scientist

    sig do
      overridable.params(
        repository_ruleset: RepositoryRuleset,
        actor: Types::Actor,
        repository: Repository,
      ).returns(T::Array[Symbol])
    end
    def allowed_ruleset_bypass_modes(repository_ruleset, actor, repository)
      bypass_configurations = T.let(repository_ruleset.bypass_actors.to_a, T::Array[T.any(RepositoryRulesetBypassActor, String)])

      # Add the temporary "org admin" bypass mode
      bypass_configurations << repository_ruleset.bypass_mode

      bypass_configurations << "deploy_key_bypass" if repository_ruleset.deploy_key_bypass

      # For forks with push rulesets applied, we need to check bypasses from the root repo's context
      if repository_ruleset.targets_push? && repository.fork?
        repository = repository.network&.root || repository
      end

      allowed_bypass_modes(bypass_configurations, actor, repository)
    end

    sig { params(actor: Types::Actor, repository: Repository).returns(T::Boolean) }
    def actor_bypass_authorized?(actor, repository)
      case actor
      when PublicKey
        write_deploy_key?(repository, actor)
      when Bot
        repository.resources.administration.writable_by?(actor)
      when User
        ::Permissions::Enforcer.authorize(
          action: :bypass_branch_protection,
          actor: actor,
          subject: repository
        ).allow?
      else
        T.absurd(actor)
      end
    end

    sig do
      params(
        bypass_actor_configurations: T::Enumerable[T.any(BranchActorAllowance, RepositoryRulesetBypassActor, String)],
        actor: T.nilable(Types::Actor),
        repository: Repository
      ).returns(T::Array[Symbol])
    end
    def allowed_bypass_modes(bypass_actor_configurations, actor, repository)
      return [] unless actor
      T.must(actor)

      allowed_bypass_modes = Set.new

      # Find out if this actor maps to a specific User, as opposed to a Bot.
      write_deploy_key = false
      user = if actor.is_a?(User)
        actor
      else
        write_deploy_key = write_deploy_key?(repository, actor)
        actor.owner
      end

      if bypass_actor_configurations.any?
        bypass_records = bypass_actor_configurations.each_with_object([]) do |bypass, arr|
          if bypass.is_a?(String)
            if bypass == "deploy_key_bypass" && write_deploy_key
              allowed_bypass_modes << RepositoryRulesetBypassActor::BYPASS_MODES[:any]
            elsif is_org_admin?(actor, repository)
              if bypass == "org_bypass_any"
                allowed_bypass_modes << RepositoryRulesetBypassActor::BYPASS_MODES[:any]
              elsif bypass == "org_bypass_prs_only"
                allowed_bypass_modes << RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request]
              end
            end
          end

          next unless !bypass.is_a?(String) && bypass.try(:actor)
          # The legacy BranchActorAllowance doesn't support bypass modes and always use mode "any"
          mode = bypass.try(:bypass_mode) || RepositoryRulesetBypassActor::BYPASS_MODES[:any]

          if bypass.actor.is_a?(User)
            # At most one "User" bypass could possibly match a given actor, so just check here and don't add it to the array
            allowed_bypass_modes << mode if bypass.actor == user
            next
          end

          arr << { actor: bypass.actor, actor_type: bypass.actor_type, mode: mode }
        end

        # Group bypass records by type, since each type has its own matching logic and we want to avoid N+1 queries
        bypasses_by_type = bypass_records.group_by { |bypass| bypass[:actor_type] }

        if user
          # Check for bypass granted due to team membership
          if bypasses_by_type.has_key?("Team")
            T.must(bypasses_by_type["Team"])
              .group_by { |bypass| bypass[:mode] }
              .each do |mode, team_bypass|
                team_ids = team_bypass.map { |bypass| bypass[:actor].id }
                allowed_bypass_modes << mode if Team.member_of?(team_ids, user.id, immediate_only: false)
              end
          end

          # Check for bypass granted due to enterprise owner membership
          if repository.enterprise_owner_bypass_enabled? &&
            bypasses_by_type.has_key?("EnterpriseOwner")
            T.must(bypasses_by_type["EnterpriseOwner"])
            .group_by { |bypass| bypass[:mode] }
            .each do |mode, _owner_bypass|
              if repository.business&.owner?(user)
                allowed_bypass_modes << mode
              end
            end
          end

          # Check for bypass granted due to enterprise team membership
          if repository.enterprise_rulesets_enterprise_teams_enabled? &&
            bypasses_by_type.has_key?("EnterpriseTeam")
            T.must(bypasses_by_type["EnterpriseTeam"])
            .group_by { |bypass| bypass[:mode] }
            .each do |mode, team_bypass|
              team_ids = team_bypass.map { |bypass| bypass[:actor].id }
              teams = EnterpriseTeam.where(id: team_ids)
              team = teams.find { |team| team.member?(user) }
              allowed_bypass_modes << mode if team
            end
          end

          # Check for bypass granted due to repo role (via user role or team role)
          if bypasses_by_type.has_key?("RepositoryRole")
            role_bypasses = T.must(bypasses_by_type["RepositoryRole"])
            builtin_role_bypasses, custom_role_bypasses = role_bypasses.partition { |bypass| Team::ABILITIES_TO_PERMISSIONS.has_key?(bypass[:actor].name) }

            # Built-in roles use this hash to implement inheritance
            if builtin_role_bypasses.any?
              user_roles = repository.permissions_hash_for(actor: user)

              builtin_role_bypasses.each do |bypass|
                # Allow bypass if the user has the role or is a write deploy key
                if user_roles[Team::ABILITIES_TO_PERMISSIONS[bypass[:actor].name].to_sym] ||
                  (write_deploy_key && bypass[:actor].target_type == "Repository")
                  allowed_bypass_modes << bypass[:mode]
                end
              end
            end

            # Custom roles need to use a DB query
            if custom_role_bypasses.any? && repository.in_organization?
              role_ids = custom_role_bypasses.map { |bypass| bypass[:actor] }.pluck(:id)
              query = UserRole.where(role_id: role_ids, target_type: "Repository", target_id: repository.id)
              matches = query
                .where(actor_type: "Team", actor_id: user.teams.pluck(:id)) # Custom role assigned to team user is member of
                .or(query.where(actor_type: "User", actor_id: user.id))     # Custom role assigned to user

              matches.each do |match|
                custom_role_bypasses.find { |bypass| bypass[:actor].id == match.role_id }.tap do |bypass|
                  allowed_bypass_modes << bypass[:mode] if bypass
                end
              end
            end
          end
        end

        # Check bypass allowances for this integration
        if actor.is_a?(Bot) && actor.integration
          actor_integration_id = T.must(actor.integration).id

          # Check for bypass granted to specific installation of this integration
          if bypasses_by_type.has_key?("IntegrationInstallation")
            installation_bypasses = T.must(bypasses_by_type["IntegrationInstallation"])
            installation_ids = installation_bypasses.map { |bypass| bypass[:actor] }.pluck(:id)

            matching_installs = IntegrationInstallation.where(id: installation_ids, integration_id: actor_integration_id)

            matching_installs.each do |install|
              installation_bypasses.find { |bypass| bypass[:actor].id == install.id }.tap do |bypass|
                allowed_bypass_modes << bypass[:mode] if bypass
              end
            end
          end

          # Check for bypass granted to this integration
          if bypasses_by_type.has_key?("Integration")
            integration_bypasses = T.must(bypasses_by_type["Integration"])

            integration_bypasses.find { |bypass| bypass[:actor].id == actor_integration_id }.tap do |bypass|
              allowed_bypass_modes << bypass[:mode] if bypass
            end
          end
        end
      end

      allowed_bypass_modes.map { |mode| RepositoryRulesetBypassActor::BYPASS_MODES.key(mode).to_sym }
    end

    # Internal: is the actor a writable deploy key? These are treated as admins
    # for the purposes of overriding protected branch requirements. See
    # https://github.com/github/github/issues/69229 for discussion.
    sig { params(repository: Repository, actor: PublicKey).returns(T::Boolean) }
    def write_deploy_key?(repository, actor)
      return false if !actor.is_a?(PublicKey)
      return false if !actor.respond_to?(:read_only?) || actor.read_only?
      return false if repository != actor.repository
      true
    end

    private

    sig { params(actor: T.nilable(Types::Actor), repository: Repository).returns(T::Boolean) }
    def is_org_admin?(actor, repository)
      return false if !actor || !repository.owner.is_a?(Organization)
      org = T.cast(repository.owner, Organization)

      if actor.is_a?(Bot)
        return org.resources.organization_administration.writable_by?(actor)
      elsif actor.is_a?(User)
        user = actor
      elsif actor.created_by_user?
        if org.rules_disallow_deploy_key_org_bypass?
          return false
        end
        user = actor.owner
      end

      !!(user && org.adminable_by?(user))
    end
  end
end
