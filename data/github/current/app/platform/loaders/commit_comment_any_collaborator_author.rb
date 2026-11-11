# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CommitCommentAnyCollaboratorAuthor < Platform::Loader
      def self.load(repository_id, commit_oid, path, position)
        self.for.load([repository_id, commit_oid, path, position])
      end

      def fetch(thread_identifiers)
        scope = thread_identifiers.reduce(::CommitComment.none) do |scope, (repository_id, commit_oid, path, position)|
          scope.or(::CommitComment.where({
            repository_id: repository_id,
            commit_id: commit_oid,
            path: path,
            position: position,
          }))
        end

        threads = Hash.new { |h, k| h[k] = [] }
        commented_user_ids = Hash.new { |h, k| h[k] = Set.new }

        scope.pluck(:repository_id, :commit_id, :path, :position, :user_id).each do |repository_id, commit_oid, path, position, user_id|
          commented_user_ids[repository_id] << user_id
          threads[[repository_id, commit_oid, path, position]] << user_id
        end

        access_user_ids = {}
        Repository.where(id: threads.keys.map(&:first).uniq).each do |repository|
          access_user_ids[repository.id] = repository.user_ids_with_privileged_access(min_action: :write, actor_ids_filter: commented_user_ids[repository.id].to_a)
        end

        results = Hash.new(false)
        threads.each do |thread_key, user_ids|
          repository_id, commit_oid, path, position = *thread_key
          results[thread_key] = (access_user_ids[repository_id] & user_ids).any?
        end

        results
      end
    end
  end
end
