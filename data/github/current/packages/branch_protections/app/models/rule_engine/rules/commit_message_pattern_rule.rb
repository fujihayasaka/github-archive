# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class CommitMessagePatternRule < MetadataPatternRule
      sig { void }
      def initialize
        super(rule_name: "commit_message_pattern", display_name: "Restrict commit messages")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:commit]
      end

      sig { override.returns(String) }
      def property_name
        "commit.message"
      end

      sig { override.returns(String) }
      def property_description
        "Commit message"
      end

      sig { override.params(candidate: MetadataSources::Types::Candidate).returns(T.nilable(String)) }
      def property_value(candidate)
        T.cast(candidate, MetadataSources::Types::CommitCandidate).message
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
        # Skip if evaluating from merge box and head SHA is the system generated PR merge commit
        return EvaluationResult.success(candidate: candidate) if context.merge_box_evaluation? && T.cast(candidate, MetadataSources::Types::CommitCandidate).oid == ref_update.after_oid

        super
      end
    end
  end
end
