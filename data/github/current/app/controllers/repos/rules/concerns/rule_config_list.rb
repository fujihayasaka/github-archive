# typed: strict
# frozen_string_literal: true

module Repos
  module Rules
    module Concerns
      module RuleConfigList
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { ApplicationController }

        # Hooks

        sig do
          params(source: T.nilable(T.any(Repository, Organization, Business)), user: T.nilable(User)).void
        end
        def rule_config_list_enabled(source: nil, user: nil)
          render_404 unless (
            source&.feature_enabled_for_source?(:rule_config_list) ||
            user&.feature_flag_enabled?(:rule_config_list, default: false)
          )
        end

        sig { params(repository: T.nilable(Repository)).void }
        def ensure_plan_supports_rules(repository: nil)
          render_404 unless repository&.plan_supports?(:protected_branches)
        end

        sig { void }
        def ensure_ref
          render json: { error: "ref is required" }, status: :bad_request unless params[:ref].present?
        end

        sig { void }
        def ensure_branch
          render json: { error: "ref must be a branch" }, status: :bad_request unless params[:ref].start_with?("refs/heads/")
        end

        # Data

        sig { params(source: RuleEngine::Types::RuleSource, user: User, branch: String).returns(T::Array[RuleSchema]) }
        def rule_schemas_by_branch(source:, user:, branch:)
          if !source.is_a?(Repository) || !branch.present?
            return []
          end

          rule_configs = BranchRuleEvaluator.for_repository_with_branch_name(source, branch)&.rule_configs

          return [] if rule_configs.nil?

          rule_configs.group_by(&:rule_type).map do |rule_type, configs|
            impl = Repositories.domain.rulesets.registry.rule_impl_for_rule_type(rule_type)
            metadata_pattern_schema = MetadataPatternSchema.new(
              propertyDescription: impl.property_description,
              supportedOperators: impl.supported_operators
            ) if impl.is_a?(RuleEngine::MetadataPatternRule)

            RuleSchema.new(
              type: rule_type,
              displayName: impl&.display_name || rule_type,
              description: impl&.description,
              beta: impl&.beta,
              parameterSchema: impl&.parameter_schema,
              metadataPatternSchema: metadata_pattern_schema,
              ruleProviders: configs.map do |config|
                ruleset = T.cast(config, RepositoryRuleConfiguration).repository_ruleset unless config.is_a?(RuleEngine::RuntimeRuleConfig)
                RuleProvider.new(
                  id: config.provider_id,
                  name: ruleset&.name || "Branch protection",
                  type: T.must(config.provider.class.name),
                  parameters: config.parameters,
                  href: ruleset&.definition&.url(T.must(ruleset).id) || edit_repository_branches_path(source.owner, source),
                  sourceType: ruleset&.source_type || :repository,
                )
              end,
            )
          end
        end

        class RuleProvider < T::Struct
          const :id, T.nilable(Integer)
          const :name, String
          const :type, String
          const :parameters, T::Hash[String, T.untyped]
          const :href, T.nilable(String)
          const :sourceType, T.any(String, Symbol)
        end

        class MetadataPatternSchema < T::Struct
          const :propertyDescription, String
          const :supportedOperators, T::Array[{ type: String, display_name: String }]
        end

        class RuleSchema < T::Struct
          const :type, String
          const :displayName, String
          const :description, T.nilable(String)
          const :beta, T.nilable(T::Boolean)
          const :parameterSchema, T.nilable(RuleEngine::ParameterSchema::Object)
          const :metadataPatternSchema, T.nilable(MetadataPatternSchema)
          const :ruleProviders, T::Array[RuleProvider]
        end
      end
    end
  end
end
