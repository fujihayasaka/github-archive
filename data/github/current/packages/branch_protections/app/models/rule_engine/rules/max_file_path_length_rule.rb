# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class MaxFilePathLengthRule < CommitRule
      sig { void }
      def initialize
        super(
          rule_name: "max_file_path_length",
          display_name: "Restrict file path length",
          description: "Prevent commits that include file paths that exceed the specified character limit from being pushed to the commit graph.")
      end

      sig { override.returns(T.nilable(String)) }
      def minimum_ghes_version
        "3.17"
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        # TODO: Temporary fix for tests until updated to use another non-push rule
        # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        return [:push, :branch, :tag] if Rails.env.test?

        [:push]
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Field.new(name: "max_file_path_length", display_name: "Maximum file path length",
           type: :integer, required: true, allowed_range: (1..), default_value: 255,
           description: "The maximum amount of characters allowed in file paths.", ui_control: "max_file_path_length"))
        schema
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:blob]
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          candidate: MetadataSources::Types::Candidate,
        ).returns(EvaluationResult)
      end
      def evaluate_candidate(context, ref_update, rule_config, candidate)
        candidate_path = T.cast(candidate, MetadataSources::Types::BlobCandidate).path
        success = !candidate_path.present? || candidate_path.size <= rule_config.param("max_file_path_length").to_i
        EvaluationResult.new(candidate: candidate, success: success)
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          violations: T::Array[Violation],
        )
        .returns(RuleRun)
      end
      def generate_evaluation_result(context, ref_update, rule_config, violations)
        return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

        RuleRun.failure(
          rule_config: rule_config,
          ref_update: ref_update,
          message: "File paths can not be greater than #{rule_config.param("max_file_path_length")} characters.",
          violations: violations.map do |violation|
            candidate = T.cast(violation.candidate, MetadataSources::Types::BlobCandidate)
            {
              candidate: T.must(candidate.path),
              commit_oid: candidate.commit_oid
            }
          end
        )
      end
    end
  end
end
