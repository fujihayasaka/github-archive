# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class PullRequestCommitCommentThread < Platform::Loader
          def self.load(pull_request_id, commit_oid, viewer)
            self.for(viewer).load([pull_request_id, commit_oid])
          end

          def initialize(viewer)
            @viewer = viewer
          end

          def fetch(pull_request_id_commit_oid_pairs)
            fetch_placeholders(pull_request_id_commit_oid_pairs)
          end

          private

          attr_reader :viewer

          def fetch_placeholders(pull_request_id_commit_oid_pairs)
            commit_oids_by_pull_request_id = Hash.new { |hash, key| hash[key] = [] }
            pull_request_id_commit_oid_pairs.each do |pull_request_id, commit_oid|
              commit_oids_by_pull_request_id[pull_request_id] << commit_oid
            end

            start_time = Time.now.change(usec: 0)

            scope = ::CommitComment.
              filter_spam_for(viewer).
              with_pull_requests(commit_oids_by_pull_request_id)


            result = scope.
              pluck(
                Arel.sql("`pull_requests`.`id`"),
                Arel.sql("`commit_comments`.`repository_id`"),
                Arel.sql("`commit_comments`.`commit_id`"),
                Arel.sql("`commit_comments`.`path`"),
                Arel.sql("`commit_comments`.`position`"),
                Arel.sql("`commit_comments`.`created_at`")).
              group_by { |pull_request_id, repository_id, commit_id, path, position, _created_at| [pull_request_id, repository_id, commit_id, path, position] }.
              transform_values { |values| values.map { |_pull_request_id, _repository_id, _commit_id, _path, _position, created_at| created_at }.min }.
              map { |(pull_request_id, repository_id, commit_id, path, position), created_at| [pull_request_id, repository_id, commit_id, path, position, created_at] }.
              sort_by! do |pull_request_id, repository_id, commit_oid, path, position, created_at|
                [pull_request_id, repository_id, commit_oid, path || "", position || -1, created_at]
              end

            results = []

            Promise.all(result.map do |pull_request_id, repository_id, commit_oid, path, position, created_at|
              async_visible = PullRequestCommitCommentThreadVisibleCheck.load(pull_request_id, repository_id, commit_oid, path, position, created_at, viewer)

              async_visible.then do |visible|
                results << [pull_request_id, repository_id, commit_oid, path, position, created_at] if visible
              end
            end).sync

            results_by_commit_oid = results.group_by do |pull_request_id, _, commit_oid, *|
              [pull_request_id, commit_oid]
            end
            results_by_commit_oid.default_proc = -> (_, _) { [] }

            results_by_commit_oid.each_value do |results|
              results.map! do |pull_request_id, repository_id, commit_oid, path, position, created_at|
                id = ::Platform::Models::PullRequestCommitCommentThread.id_for(
                  pull_request_id, repository_id, commit_oid, path, position
                )

                thread = ::Timeline::Placeholder::PullRequestCommitCommentThread.new(
                  id: id, sort_datetimes: [created_at]
                )
                thread.commit_oid = commit_oid
                thread
              end
            end
          end
        end
      end
    end
  end
end
