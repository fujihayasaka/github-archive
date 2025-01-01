# typed: true
# frozen_string_literal: true

module RuleEngine
  module Bypasses
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
        bypass_actor_configurations: T::Array[T.any(BranchActorAllowance, RepositoryRulesetBypassActor, String)],
        actor: T.nilable(Types::Actor),
        repository: Repository
      ).returns(T::Array[Symbol])
    end
    def allowed_bypass_modes(bypass_actor_configurations, actor, repository)
      return [] unless actor
      T.must(actor)

      bypass_actors = bypass_actor_configurations.reject { |bypass| bypass.is_a?(String) }
      return [] unless bypass_actors.any?
      modes = []

      bypassers = T.cast(bypass_actors.select { |bypass| bypass.is_a?(RepositoryRulesetBypassActor) }, T::Array[RepositoryRulesetBypassActor])
      modes = RepositoryRulesetBypassActor.all_allowed_bypass_modes(bypassers, actor, repository)

      user = actor.is_a?(User) ? actor : actor.owner

      if user.is_a?(User)
        branch_actor_allowances = T.cast(bypass_actors.select { |bypass| bypass.is_a?(BranchActorAllowance) }, T::Array[BranchActorAllowance])
        bypassers_by_type = branch_actor_allowances.group_by { |bypass| bypass.actor_type }
        if bypassers_by_type["User"]&.map(&:actor_id)&.include?(user.id)
          modes << :any
        end

        team_ids = bypassers_by_type["Team"]&.map(&:actor_id)
        if team_ids
          modes << :any if Team.member_of?(team_ids, user.id, immediate_only: false)
        end

        if actor.is_a?(Bot) && actor.integration
          actor_integration_id = T.must(actor.integration).id

          # Check for bypass granted to specific installation of this integration
          if bypassers_by_type.has_key?("IntegrationInstallation")
            installation_bypassers = T.must(bypassers_by_type["IntegrationInstallation"])
            bypasser_ids = installation_bypassers.map(&:actor_id)
            matching_installs = IntegrationInstallation.where(id: bypasser_ids, integration_id: actor_integration_id).any?
            modes << :any if matching_installs
          end
        end
      end
      modes.compact.uniq
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
