# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class MergeBoxConfirmationEvent < GitEvent
      sig do
        params(
          repository: Repository,
          actor: Types::Actor,
          qualified_ref_name: String,
          before_oid: String,
          commit_message: T.nilable(String),
          allow_empty_commit_message: T.nilable(T::Boolean),
          committer_email: T.nilable(String),
          author_email: T.nilable(String),
        ).void
      end
      def initialize(repository, actor, qualified_ref_name:, before_oid:, commit_message:, allow_empty_commit_message: false, committer_email: nil, author_email: nil)
        @allow_empty_commit_message = allow_empty_commit_message
        @commit_message = commit_message

        metadata_source = RuleEngine::MetadataSources::Local.new(
          commits: [
            RuleEngine::MetadataSources::Types::CommitCandidate.new(
              oid: nil,
              gpg_signature: nil,
              message: commit_message,
              committer_email:,
              author_email:,
            )
          ],
          blobs: [],
        )

        ref_updates = [Git::Ref::Update.new(
          repository:,
          refname: qualified_ref_name,
          before_oid:,
          after_oid: GitHub::PENDING_OID,
        )]

        super(
          repository,
          ref_updates,
          actor,
          metadata_source:,
          phase: RuleEngine::Types::Phase::PostReceive,
          commit_refs: false)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        {
          merge_box_evaluation: true,
          commit_refs_evaluation: false,
          server_merge: false,
          fetch_and_merge: false,
        }
      end

      sig { override.params(rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RepositoryRuleConfiguration]) }
      def before_evaluation(rule_configs)
        rule_configs.filter do |rule_config|
          next false unless rule_config.rule_type == "commit_message_pattern"
          next false if @allow_empty_commit_message && @commit_message.blank?

          true
        end
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites.each do |suite|
          suite.evaluation_metadata.merge!(pull_request_metadata(suite.ref_update))
        end

        rule_suites + skipped_ref_updates.map { |ref_update| RuleSuite.success(repository, ref_update, actor) }
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).void }
      def record_results(rule_suites)
        # Don't save suites or produce logs for merge box events
      end
    end
  end
end
