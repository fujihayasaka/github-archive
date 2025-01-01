# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CommitOidRule < CommitRule
      sig { void }
      def initialize
        super(
          rule_name: "commit_oid",
          display_name: "Restrict commit IDs",
          description: "Prevent commits to targets by commit ID.",
          feature_flag: :new_restricted_commits_rule
        )
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:commit]
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        restricted_commit_schema = ParameterSchema::Object.new(name: "restricted_commits", display_name: "Restricted commit", description: "Restricted commit")
        restricted_commit_schema.add_field(ParameterSchema::Field.new(name: "oid", display_name: "Commit ID",
            type: :string, required: true, description: "Full or abbreviated commit hash to reject"))
        restricted_commit_schema.add_field(ParameterSchema::Field.new(name: "reason", display_name: "Reason",
          type: :string, required: false, description: "Reason for restriction"))

        schema.add_field(ParameterSchema::Array.new(name: "restricted_commits", display_name: "Restricted commits",
          required: true, content_type: :object, content_object: restricted_commit_schema, description: "Restricted commits",
          ui_control: "restricted_commits"))
        schema
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
        oids = rule_config.param("restricted_commits").map { |c| c["oid"] }.compact
        success = !oids.include?(T.cast(candidate, MetadataSources::Types::CommitCandidate).oid)
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
          message: "Commits cannot contain rejected OIDs",
          violations: violations.map do |violation|
            {
              candidate: T.must(T.cast(violation.candidate, MetadataSources::Types::CommitCandidate).oid)
            }
          end
        )
      end
    end
  end
end
