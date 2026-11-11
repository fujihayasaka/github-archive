# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources
    class Local < Base
      sig { params(blobs: T::Array[Types::BlobCandidate], commits: T::Array[Types::CommitCandidate]).void }
      def initialize(blobs: [], commits: [])
        @blobs = blobs
        @commits = commits
      end

      sig { override.returns(String) }
      def name
        "local"
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(Collection[Types::BlobCandidate]) }
      def blobs(repository, phase, ref_update, cursor)
        return Collection.new @blobs, nil unless @blobs.any? &&
          ref_update.before_oid != GitHub::NULL_OID &&
          (ref_update.after_oid == GitHub::NULL_OID || ref_update.after_oid == GitHub::PENDING_OID)

        ##
        # We need to load all the blobs, recursively, for the directory being deleted. This is currently only necessaary
        # when deleting an entire directory from the UI. Because we need to individually process each blob input, we must keep track
        # of the current blob index and the Spokes API cursor.
        #
        next_index, next_spokes_cursor = if cursor.nil?
          [0, nil]
        else
          parsed_cursor = cursor.split(" ")
          [parsed_cursor.first.to_i, parsed_cursor.second]
        end

        result = T.let([], T::Array[Types::BlobCandidate])

        T.must(@blobs[next_index..]).each_with_index do |blob, index|
          break if result.size >= 1000

          if !blob.path&.end_with?("/")
            next_spokes_cursor = nil
            next_index = next_index + index + 1
            result.push(blob)
            next
          end

          tree_oid = repository.tree(ref_update.before_oid, blob.path)&.oid
          raise ArgumentError, "Could not find tree for #{blob.path}" if tree_oid.nil?

          spokes_cursor = GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor: next_spokes_cursor) if next_spokes_cursor.present?

          tree_entries_result = repository.spokes_api.list_tree_entries(tree_oid:, recursive: true, cursor: spokes_cursor)

          next_spokes_cursor = tree_entries_result.next_cursor&.cursor
          next_index = next_index + index + 1 if next_spokes_cursor.nil?

          tree_entries_result.entries.each do |tree_entry|
            next unless tree_entry.object.type == :TYPE_BLOB

            result.push(
              Types::BlobCandidate.new(
                oid: tree_entry.object.oid.id,
                commit_oid: ref_update.before_oid,
                path: T.must(blob.path) + tree_entry.path.name,
                size: tree_entry.object.size,
                # We don't need the blob's contents as this is currently only invoked when deleting directories from the UI.
                contents: nil,
              )
            )
          end
        end

        next_cursor = [next_index, next_spokes_cursor].join(" ") if next_index < @blobs.size

        Collection.new result, next_cursor
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(Collection[Types::CommitCandidate]) }
      def commits(repository, phase, ref_update, cursor)
        Collection.new @commits, nil
      end
    end
  end
end
