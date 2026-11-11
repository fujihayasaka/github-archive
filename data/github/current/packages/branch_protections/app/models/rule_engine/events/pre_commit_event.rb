# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class PreCommitEvent < GitEvent
      include GitHub::Memoizer

      PreCommitMetadata = T.type_alias { { message: T.nilable(String), author_email: T.nilable(String), committer_email: T.nilable(String), blobs: T::Hash[String, T.nilable(String)] } }

      sig do
        params(
          repository: Repository,
          actor: Types::Actor,
          target: T.nilable(String),
          metadata: PreCommitMetadata,
          target_ref_name: T.nilable(String)
        ).void
      end
      def initialize(repository, actor, target:, metadata:, target_ref_name: nil)
        commits = [
          RuleEngine::MetadataSources::Types::CommitCandidate.new(
            oid: nil,
            gpg_signature: nil,
            message: metadata[:message],
            committer_email: metadata[:committer_email],
            author_email: metadata[:author_email],
          ),
        ]

        blobs = metadata[:blobs].map do |path, contents|
          RuleEngine::MetadataSources::Types::BlobCandidate.new(
            oid: nil,
            commit_oid: nil,
            path:,
            # NOTE: This is an approximation and may not reflect the actual size of the blob on disk.
            size: contents&.bytesize || 0, # We fallback to 0 when contents is nil. This indicates that the file is empty.
            contents: contents,
          )
        end

        metadata_source = RuleEngine::MetadataSources::Local.new(
          commits:,
          blobs:,
        )

        ref_updates = [Git::Ref::Update.new(
          repository:,
          refname: target_ref_name || GitHub::UNKNOWN_REF_NAME,
          before_oid: target || GitHub::NULL_OID,
          after_oid: GitHub::PENDING_OID,
        )]

        super(
          repository,
          ref_updates,
          actor,
          metadata_source:,
          phase: RuleEngine::Types::Phase::PreReceive,
          commit_refs: false)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        {
          merge_box_evaluation: false,
          commit_refs_evaluation: false,
          server_merge: false,
          fetch_and_merge: false
        }
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites.each do |suite|
          suite.evaluation_metadata.merge!(pull_request_metadata(suite.ref_update))
        end

        rule_suites + skipped_ref_updates.map { |ref_update| RuleSuite.success(repository, ref_update, actor) }
      end

      sig { override.params(rule_suites: T::Array[RuleEngine::RuleSuite]).void }
      def record_results(rule_suites)
        super

        GitHub.context.push(repository_rules_engine_pre_receive_rule_suites: rule_suites.map(&:id))
      end

      sig { override.params(exception: StandardError).returns(T::Array[RuleSuite]) }
      def handle_exception(exception)
        rule_suites = super(exception)
        ProtectedBranchLegacyInstrumenter.instrument_decision(rule_suites, repository)
        rule_suites
      end
    end
  end
end
