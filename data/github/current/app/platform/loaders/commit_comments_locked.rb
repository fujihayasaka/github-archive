# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CommitCommentsLocked < Platform::Loader
      def self.load(repository_id, commit_oid)
        self.for(repository_id).load(commit_oid)
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(commit_ids)
        results = IssueEvent.connection.select_rows(Arel.sql(<<-SQL, repository_id: @repository_id, commit_ids: commit_ids, event_types: ::Commit::EVENT_TYPES))
          SELECT id, commit_id, event FROM issue_events
          WHERE repository_id = :repository_id
            AND issue_id IS NULL
            AND commit_id IN (:commit_ids)
            AND event IN (:event_types)
        SQL

        locked = results.group_by { |_id, commit_id, _event_type| commit_id }.map do |commit_id, events|
          _, _, event_type = events.max_by { |id, _commit_id, _event_type| id }

          [commit_id, event_type == "locked"]
        end.to_h

        commit_ids.map do |commit_id|
          [commit_id, locked.fetch(commit_id, false)]
        end.to_h
      end
    end
  end
end
