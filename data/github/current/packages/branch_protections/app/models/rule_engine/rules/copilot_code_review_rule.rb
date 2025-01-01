# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CopilotCodeReviewRule < RefUpdateRule

      sig { void }
      def initialize
        super(rule_name: "copilot_code_review",
              display_name: "Automatically request Copilot code review",
              description: "Request Copilot code review for new pull requests automatically if the author has access to Copilot code review.")
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(
          name: "review_on_push",
          display_name: "Review new pushes",
          description: "Copilot automatically reviews each new push to the pull request.",
          type: :boolean,
          default_value: false,
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "review_draft_pull_requests",
          display_name: "Review draft pull requests",
          description: "Copilot automatically reviews draft pull requests before they are marked as ready for review.",
          type: :boolean,
          default_value: false,
        ))
        schema
      end

      sig { override.params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.15"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # don't actually block anything
        []
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def copilot_code_review_enabled?
          configs_by_type("copilot_code_review").any?
        end

        sig { returns(T::Boolean) }
        def copilot_code_review_on_push_enabled?
          configs_by_type("copilot_code_review").any? { |c| c.param("review_on_push") }
        end

        sig { returns(T::Boolean) }
        def copilot_code_review_draft_pull_requests_enabled?
          configs_by_type("copilot_code_review").any? { |c| c.param("review_draft_pull_requests") }
        end
      end
    end
  end
end
