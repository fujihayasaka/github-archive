# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class TagNamePatternRule < MetadataPatternRule
      sig { void }
      def initialize
        super(rule_name: "tag_name_pattern", display_name: "Restrict tag names")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:ref]
      end

      sig { override.returns(String) }
      def property_name
        "tag.name"
      end

      sig { override.returns(String) }
      def property_description
        "Tag name"
      end

      sig { override.params(candidate: MetadataSources::Types::Candidate).returns(T.nilable(String)) }
      def property_value(candidate)
        T.cast(candidate, Git::Ref::Update).refname.delete_prefix("refs/tags/")
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
        ref_update_candidate = T.cast(candidate, Git::Ref::Update)
        return EvaluationResult.success(candidate: candidate) unless ref_update_candidate.tag? && ref_update_candidate.creation?

        super
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:tag]
      end
    end
  end
end
