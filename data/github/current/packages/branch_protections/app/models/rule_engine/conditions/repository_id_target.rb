# typed: true
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RepositoryIdTarget < ConditionTarget

      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:organization]
      end

      sig { override.returns(TargetObject) }
      def target_object
        TargetObject::Repository
      end

      sig { override.returns(T::Array[Targetable::Attribute]) }
      def targeted_attributes
        [Targetable::Attribute::Repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:branch, :tag, :push, :repository]
      end

      sig do
        override.params(
          target_attributes: T::Hash[Targetable::Attribute, T.untyped],
          parameters: T::Hash[String, T.untyped],
        ).returns(T::Boolean)
      end
      def run_condition(target_attributes, parameters)
        return false unless (repository = target_attributes[Targetable::Attribute::Repository]).is_a?(Repository)

        parameters["repository_ids"]&.include?(repository.global_relay_id) || false
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Array.new(name: "repository_ids", display_name: "Included repo IDs",
           required: true, content_type: :node_id, description: "One of these repo IDs must match the repo.",
           validator: method(:ensure_valid_repos)))

        schema
      end

      sig do
        override.params(ruleset: RepositoryRuleset, parameters: T::Hash[String, T.untyped])
        .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
      end
      def edit_ui_metadata(ruleset, parameters)
        repo_node_ids = parameters["repository_ids"]
        return nil unless repo_node_ids && repo_node_ids.size > 0
        return nil unless ruleset.source_type == "User" # Organization

        repos = repos_for_node_ids(repo_node_ids, ruleset.source_id)
        GitHub::PrefillAssociations.prefill_associations(repos, :owner)

        {
          repositories: repos.map { |repo| RulesEngine::ReactPayload.simple_repository_payload(repo) }
        }
      end

      private

      def repos_for_node_ids(repo_node_ids, source_id)
        repo_ids = repo_node_ids.map { |id| Platform::Helpers::NodeIdentification.from_global_id(id)[1] }
        Repositories::Public.filter_repo_ids_to_org(repo_ids: repo_ids, organization_id: source_id)
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          repo_node_ids: T::Array[String],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_repos(context, repo_node_ids, errors)
        source = context.root["ruleset_source"]
        target = context.root["ruleset_target"]

        repos = repos_for_node_ids(repo_node_ids, source.id)

        errors << {
          error_code: :invalid,
          message: "repository ids cannot be empty",
        } if repo_node_ids.empty?

        if target == "push" && source.is_a?(Organization)
          has_public_repos = repos.where(public: true).any?
          if has_public_repos
            errors << {
              error_code: :public_repos_in_push_rule,
              message: "public repositories cannot be targeted by push rulesets",
            }
          end
        end

        if repos.size != repo_node_ids.size
          errors << {
            error_code: :repository_not_available,
            message: "repository selected does not exist or is not in this organization",
          }
        end
      end
    end
  end
end
