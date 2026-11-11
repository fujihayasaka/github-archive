# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Rules
      class BaseRuleMigrator
        include GitHub::Memoizer
        extend T::Helpers

        abstract!

        sig { abstract.returns(Symbol) }
        def rule_type; end

        sig { abstract.returns(String) }
        def display_name; end

        sig { overridable.params(protected_branch: ::ProtectedBranch).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def parameters(protected_branch)
          {}
        end

        sig do
          overridable.params(protected_branch: ::ProtectedBranch)
            .returns(T.nilable(Structs::TranslationResult))
        end
        def translate(protected_branch)
          return nil if ::ProtectedBranch::LEVELS[enforcement_level(protected_branch)] == ::ProtectedBranch::LEVELS[:off]

          Structs::TranslationResult.new(
            rule_type: rule_type.to_s,
            parameters: parameters(protected_branch),
            bypass_actors: extract_bypass_actors(protected_branch),
          )
        end

        sig do
          abstract.params(
            protected_branch: ::ProtectedBranch,
            rulesets: T::Array[::RepositoryRuleset]
          ).returns(T::Boolean)
        end
        def verify(protected_branch, rulesets); end

        sig do
          overridable.params(
            protected_branch: ::ProtectedBranch,
            rule_configs: T::Array[::RuleEngine::IRuleConfig],
            rulesets: T::Array[::RepositoryRuleset],
          ).returns(Structs::Coverage)
        end
        def coverage(protected_branch, rule_configs, rulesets)
          configs = filtered_rule_configs(rule_configs)

          return Structs::Coverage.none(display_name) if configs.empty?

          bypass_actor_coverage(protected_branch, configs, rulesets)
        end

        sig { params(protected_branch: ::ProtectedBranch).returns(T::Boolean) }
        def is_enabled?(protected_branch)
          ::ProtectedBranch::LEVELS[enforcement_level(protected_branch)] != ::ProtectedBranch::LEVELS[:off]
        end

        private

        sig { params(protected_branch: ::ProtectedBranch).returns(T::Array[Structs::BypassActor]) }
        def extract_bypass_actors(protected_branch)
          return [] unless ::ProtectedBranch::LEVELS[enforcement_level(protected_branch)] == ::ProtectedBranch::LEVELS[:non_admins]

          [Structs::BypassActor.new(
            actor_type: "RepositoryRole",
            actor_id: repo_admin_role.id,
            bypass_mode: "always"
          )]
        end

        sig { params(rule_configs: T::Array[::RuleEngine::IRuleConfig]).returns(T::Array[RepositoryRuleConfiguration]) }
        def filtered_rule_configs(rule_configs)
          T.cast(rule_configs.select do |config|
            config.rule_type == rule_type.to_s
          end, T::Array[RepositoryRuleConfiguration])
        end

        sig do
          params(
            protected_branch: ::ProtectedBranch,
            rule_configs: T::Array[RepositoryRuleConfiguration],
            rulesets: T::Array[::RepositoryRuleset],
          ).returns(Structs::Coverage)
        end
        def bypass_actor_coverage(protected_branch, rule_configs, rulesets)
          protected_branch_bypass_actors = extract_bypass_actors(protected_branch)

          most_restrictive = rule_configs.reduce(:no_rulesets) do |result, config|
            next result if result == :admin_disallowed
            ruleset = rulesets.find { |r| r.id == config.repository_ruleset_id }
            next result if ruleset.nil?
            bypass_actors = ruleset.bypass_actors
            next :admin_disallowed if bypass_actors.empty?
            next :only_admin if bypass_actors.all? { |ba| ba.actor == repo_admin_role }
            next :bypass_actor_mismatch if bypass_actors.any? do |ba|
              protected_branch_bypass_actors.none? { |pba| pba.actor_type == ba.actor_type && pba.actor_id == ba.actor_id }
            end
            next :non_admin_bypass
          end

          if most_restrictive == :no_rulesets
            Structs::Coverage.none(display_name)
          elsif most_restrictive == :admin_disallowed || (most_restrictive == :only_admin && enforcement_level(protected_branch) == "non_admins")
            Structs::Coverage.full
          else
            Structs::Coverage.new(
              status: Structs::CoverageStatus::PartiallyCovered,
              gaps: ["Rulesets specify bypass actors"],
            )
          end
        end

        sig { abstract.params(protected_branch: ::ProtectedBranch).returns(String) }
        def enforcement_level(protected_branch); end

        sig { returns(T.untyped) }
        memoize def repo_admin_role
          T.let(::RepositoryRole.find_by(owner_id: nil, name: "admin"), T.untyped)
        end
      end
    end
  end
end
