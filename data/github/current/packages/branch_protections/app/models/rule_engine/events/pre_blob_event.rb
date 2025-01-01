# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class PreBlobEvent < PreCommitEvent
      PreBlobMetadata = T.type_alias { { blobs: T::Hash[String, T.nilable(String)] } }

      sig do
        params(
          repository: Repository,
          actor: Types::Actor,
          metadata: PreBlobMetadata,
        ).void
      end
      def initialize(repository, actor, metadata:)
        super(
          repository,
          actor,
          target: nil,
          metadata: {
            message: nil,
            author_email: nil,
            committer_email: nil,
            blobs: metadata[:blobs]
          }
        )
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        super.merge({
          blob_evaluation: true,
        })
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites.each do |suite|
          suite.evaluation_metadata.merge!({
            blob_evaluation: true
          })
        end

        super(rule_suites)
      end
    end
  end
end
