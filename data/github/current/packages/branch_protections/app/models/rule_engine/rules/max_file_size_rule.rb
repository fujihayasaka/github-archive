# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class MaxFileSizeRule < CommitRule
      sig { void }
      def initialize
        super(
          rule_name: "max_file_size",
          display_name: "Restrict file size",
          description: "Prevent commits that exceed a specified file size limit from being pushed to the commit.",
          feature_flag: :push_rulesets)
      end

      # Remove once push_rulesets ff is removed
      sig { override.returns(T::Boolean) }
      def publish_api
        true
      end

      sig { override.returns(T.nilable(String)) }
      def minimum_ghes_version
        "3.16"
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:push]
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Field.new(name: "max_file_size", display_name: "Maximum file size",
          type: :integer, required: true, allowed_range: (1..100), default_value: 10,
          description: "The maximum file size allowed in megabytes. This limit does not apply to Git Large File Storage (Git LFS).",
          ui_control: "max_file_size"))
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
          candidate: RuleEngine::MetadataSources::Types::Candidate,
        ).returns(EvaluationResult)
      end
      def evaluate_candidate(context, ref_update, rule_config, candidate)
        success = T.must((T.cast(candidate, RuleEngine::MetadataSources::Types::BlobCandidate).size)) <= convert_to_bytes(rule_config.param("max_file_size").to_i)
        EvaluationResult.new(candidate: candidate, success: success)
      end

      sig do
        override
        .params(
          context: RuleEngine::RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          violations: T::Array[Violation]
        )
        .returns(RuleEngine::RuleRun)
      end
      def generate_evaluation_result(
        context,
        ref_update,
        rule_config,
        violations
      )
        return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

        RuleRun.failure(
          rule_config: rule_config,
          ref_update: ref_update,
          message: "File size can not exceed #{rule_config.param("max_file_size")} MB.",
          violations: violations.map do |violation|
            candidate = T.cast(violation.candidate, MetadataSources::Types::BlobCandidate)
            {
              candidate: candidate.path || "",
              commit_oid: candidate.commit_oid
            }
          end
        )
      end

      private

      sig { params(size_in_mb: Integer).returns(Integer) }
      def convert_to_bytes(size_in_mb)
        size_in_mb * 1024 * 1024
      end
    end
  end
end
