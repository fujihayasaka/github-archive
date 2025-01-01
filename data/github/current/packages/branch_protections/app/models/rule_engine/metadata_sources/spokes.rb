# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources

    class Spokes < Base
      include Scientist

      sig { override.returns(String) }
      def name
        "spokes"
      end

      # An unexpected error occurred while fetching data from Spokes
      class UnexpectedError < StandardError

        sig { params(error: String).void }
        def initialize(error)
          super("Unexpected error from Spokes: #{error}")
        end
      end

      # An object could not be fetched from Spokes
      class ObjectMissing < StandardError
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate]) }
      def blobs(repository, phase, ref_update, cursor)
        return Collection.new([], nil) if ref_update.deletion?

        pushed_blobs(repository, ref_update, cursor)
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::CommitCandidate]) }
      def commits(repository, phase, ref_update, cursor)
        return Collection.new([], nil) if ref_update.deletion?

        reference_updates = [{
          ref_name: ref_update.refname,
          previous_ref_oid: ref_update.before_oid,
          current_ref_oid: ref_update.after_oid,
        }]

        spokes_cursor = GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor:) if cursor.present?

        result = if ref_update.creation? || phase == RuleEngine::Types::Phase::PreReceive
          repository.spokes_api.list_newly_reachable_commits(
            reference_updates: reference_updates,
            cursor: spokes_cursor,
            base_repository_id: get_root_repository_id(repository),
            read_uncommitted: true,
          )
        else
          repository.spokes_api.list_historical_commits(
            reference_updates: reference_updates,
            cursor: spokes_cursor,
            read_uncommitted: true,
          )
        end

        candidates = T.let([], T::Array[RuleEngine::MetadataSources::Types::CommitCandidate])
        result.commits.map do |commit|
          candidates.push(Types::CommitCandidate.from_spokes(commit))
        end

        Collection.new(candidates, result.next_cursor&.cursor)
      end

      private

      sig do
        params(
          repository: Repository,
          ref_update: Git::Ref::Update,
          cursor: T.nilable(String))
        .returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate])
      end
      def pushed_blobs(repository, ref_update, cursor)
        GitHub.dogstats.distribution_time("repository_rules_engine.metadata.spokes.duration", tags: ["metadata_type:blob", "method:pushed_blobs"]) do
          reference_updates = [{
            ref_name: ref_update.refname,
            previous_ref_oid: ref_update.before_oid,
            current_ref_oid: ref_update.after_oid,
          }]

          spokes_cursor = GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor:) if cursor.present?

          result = repository.spokes_api.list_pushed_blobs(
            reference_updates: reference_updates,
            cursor: spokes_cursor,
            base_repository_id: get_root_repository_id(repository),
          )

          candidates = T.let([], T::Array[RuleEngine::MetadataSources::Types::BlobCandidate])
          result.pushed_blobs.map do |blob|
            candidates.push(Types::BlobCandidate.from_spokes_pushed_blob_item(blob))
          end

          GitHub.dogstats.count("repository_rules_engine.metadata.spokes.calls", 1, tags: ["metadata_type:blob", "method:pushed_blobs"])
          Collection.new(candidates, result.next_cursor&.cursor)
        end
      end

      sig { params(repository: Repository).returns(T.nilable(Integer)) }
      def get_root_repository_id(repository)
        return nil unless repository.fork?
        return repository.network&.root_id unless repository.network.nil?

        raise "Repository #{repository.id} is a fork, but has no network."
      end
    end
  end
end
