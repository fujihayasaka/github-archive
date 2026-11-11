# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class AuthorizationRule < RefUpdateRule

      def initialize
        super(rule_name: "authorization",
              display_name: "Restrict who can push")
      end

      # The authorization policy is directly tied to the ProtectedBranch model
      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        rule_configs.map do |config|
          if config.source.is_a?(ProtectedBranch) && !config.source.authorized?(context.actor)
            RuleRun.failure(rule_config: config, ref_update: ref_update, message:
              "You're not authorized to push to this branch. Visit #{DocsUrlConfig.url_for("repositories/about-protected-branches")} for more information.")
          else
            RuleRun.success(rule_config: config, ref_update: ref_update)
          end
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def authorized?(actor)
          configs_by_type("authorization").all? do |config|
            config.source.is_a?(ProtectedBranch) && config.source.authorized?(actor)
          end
        end

        def authorized_actors_only?
          configs_by_type("authorization").any?
        end
        alias_method :has_authorized_actors?, :authorized_actors_only?

        def authorized_integrations
          return [] unless has_authorized_actors?

          integration_lists = configs_by_type("authorization").map do |config|
            config.source.authorized_integration_ids if config.source.is_a?(ProtectedBranch) && config.source.has_authorized_actors?
          end.compact

          actor_ids = if integration_lists.size > 1
            integration_lists.first.intersection(*integration_lists[1..-1])
          else
            integration_lists.first
          end

          Integration.where(id: actor_ids).includes([:owner, :bot, :latest_version])
        end

        def authorized_users
          return [] unless has_authorized_actors?

          user_lists = configs_by_type("authorization").map do |config|
            config.source.authorized_user_ids if config.source.is_a?(ProtectedBranch) && config.source.has_authorized_actors?
          end.compact

          actor_ids = if user_lists.size > 1
            user_lists.first.intersection(*user_lists[1..-1])
          else
            user_lists.first
          end

          User.where(id: actor_ids)
        end

        def authorized_teams
          return [] unless has_authorized_actors?

          team_lists = configs_by_type("authorization").map do |config|
            config.source.authorized_team_ids if config.source.is_a?(ProtectedBranch) && config.source.has_authorized_actors?
          end.compact

          actor_ids = if team_lists.size > 1
            team_lists.first.intersection(*team_lists[1..-1])
          else
            team_lists.first
          end

          Team.where(id: actor_ids)
        end

        def authorized_teams_with_preloaded_org
          authorized_teams.includes(:organization)
        end
      end
    end
  end
end
