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
        extend T::Sig

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

        if repository.feature_enabled_for_repo_or_owner?(:push_rulesets_spokes_pushed_blobs)
          pushed_blobs(repository, ref_update, cursor)
        elsif repository.feature_enabled_for_repo_or_owner?(:push_rulesets_spokes_pushed_blobs_experiment)
          science "push_rulesets_spokes_pushed_blobs" do |e|
            e.use { reachable_blobs(repository, phase, ref_update, cursor) }
            e.try { pushed_blobs(repository, ref_update, cursor) }
            e.performance_only
          end
        else
          reachable_blobs(repository, phase, ref_update, cursor)
        end
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
            read_uncommited: true,
          )
        else
          repository.spokes_api.list_historical_commits(
            reference_updates: reference_updates,
            cursor: spokes_cursor,
            read_uncommited: true,
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
          phase: T.nilable(RuleEngine::Types::Phase),
          ref_update: Git::Ref::Update,
          cursor: T.nilable(String))
        .returns(T.nilable(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate]))
      end
      def reachable_blobs(repository, phase, ref_update, cursor)
        GitHub.dogstats.distribution_time("repository_rules_engine.metadata.spokes.duration", tags: ["metadata_type:blob", "method:reachable_blobs"]) do
          spokes_calls = 1

          reference_updates = [{
            ref_name: ref_update.refname,
            previous_ref_oid: ref_update.before_oid,
            current_ref_oid: ref_update.after_oid,
          }]

          spokes_cursor = GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor:) if cursor.present?

          result = if ref_update.creation? || phase == RuleEngine::Types::Phase::PreReceive
            repository.spokes_api.list_newly_reachable_blobs(
              reference_updates: reference_updates,
              cursor: spokes_cursor,
              base_repository_id: get_root_repository_id(repository),
              read_uncommited: true,
            )
          else
            repository.spokes_api.list_historical_reachable_blobs(
              reference_updates: reference_updates,
              cursor: spokes_cursor,
              read_uncommited: true,
            )
          end

          objects_by_blob_oid = if result.reachable_blobs.any?
            oids = result.reachable_blobs.filter_map do |blob|
              next if !GitHub::Spokes::Proto::Helpers::Mode.is_regular?(blob.mode)
              next if blob.status == :DIFF_STATUS_DELETION

              blob.blob_oid.id
            end

            spokes_calls += 1
            resolve_objects(repository, oids:)
          else
            {}
          end

          candidates = T.let([], T::Array[RuleEngine::MetadataSources::Types::BlobCandidate])
          result.reachable_blobs.map do |blob|
            size = if objects_by_blob_oid.key?(blob.blob_oid.id)
              T.cast(objects_by_blob_oid[blob.blob_oid.id].object.size, Integer)
            else
              0
            end

            candidates.push(Types::BlobCandidate.from_spokes(blob, size:))
          end

          GitHub.dogstats.count("repository_rules_engine.metadata.spokes.calls", spokes_calls, tags: ["metadata_type:blob", "method:reachable_blobs"])
          Collection.new(candidates, result.next_cursor&.cursor)
        end
      end

      sig do
        params(
          repository: Repository,
          ref_update: Git::Ref::Update,
          cursor: T.nilable(String))
        .returns(T.nilable(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate]))
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

      sig { params(repository: Repository, oids: T::Array[String]).returns(T::Hash[String, T.untyped]) }
      def resolve_objects(repository, oids:)
        objects_by_oid = {}

        ##
        # reachable_blobs uses boundary cursors which means that the amount of blobs returned can exceed 1000, unlike
        # the equivalent commit endpoints. Instead of sending more than 1000 OIDs to resolve_objects which will fail,
        # we request them in chunks.
        #

        oids.each_slice(1000) do |slice|
          repository.spokes_api.resolve_objects(
            oids: slice,
            read_uncommitted: true,
          )
            .items
            .each do |item|
              if item.error.present?
                case item.error
                when "missing"
                  raise ObjectMissing
                else
                  raise UnexpectedError.new(item.error)
                end
              end

              objects_by_oid[item.object.oid.id] = item
            end
        end

        objects_by_oid
      end
    end
  end
end
