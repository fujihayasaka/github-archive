# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "divvy"
require "ruby-progressbar"

module GitHub
  module Transitions
    class UpdateMilestoneNumberSequencesBase < Transition
      include Divvy::Parallelizable

      READ_BATCH_SIZE = 1000
      MAX_RETRY_COUNT = 8

      # override in sub-class.
      def table_name
        raise "override in sub-class"
      end

      def after_initialize

        @start_id =
          @other_args[:start_id] ||
          readonly { ApplicationRecord::Domain::IssuesPullRequests.github_sql.value("SELECT MIN(repository_id) FROM #{table_name.value}") || 0 }

        @end_id =
          @other_args[:end_id] ||
          readonly { ApplicationRecord::Domain::IssuesPullRequests.github_sql.value("SELECT MAX(repository_id) FROM #{table_name.value}") || 0 }

        @progress_bar = ProgressBar.create(
          total: @end_id - @start_id + 1, # think IDs 1-11, that's 11 rows.
          format: "%c/%C | %w | %a (%E)",
          throttle_rate: 1,
          title: "Update #{table_name} number sequences",
          output: Rails.env.test? ? StringIO.new : STDERR)

        @iterator = readonly do
          ApplicationRecord::Domain::IssuesPullRequests.github_sql_batched_between(
            start: @start_id,
            finish: @end_id,
            batch_size: READ_BATCH_SIZE)
        end

        # take distinct repository IDs from table in a given interval.
        @iterator.add <<~SQL, table_name: table_name
          SELECT DISTINCT repository_id
          FROM `:table_name`
          WHERE repository_id BETWEEN :start AND :last
        SQL

      end

      # Returns nothing.
      def perform
        @progress_bar.log "Starting transition #{self.class.to_s.underscore} - #{@end_id - @start_id + 1} repositories rows."

        dispatch { |rows| process(rows) }

        @progress_bar.log "Finished transition #{self.class.to_s.underscore}"
      end

      def dispatch
        @iterator.batches.each do |rows|
          next if rows.empty?

          yield rows

          # approximate approach to estimate progress.
          @progress_bar.progress = [@progress_bar.progress, rows.last.first - @start_id + 1].max
        end

        @progress_bar.finish
      end

      def process(rows)
        rows.each do |row|
          # Since this is scaled per repository, and no enterprise customer has anywhere close to the number of
          # repositories as dotcom has, writing could be one row at a time.
          repository_id = row.first

          if dry_run?
            ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
              sql = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<~SQL, repository_id: repository_id, table_name: table_name
                SELECT MAX(number) FROM `:table_name` where repository_id = :repository_id
              SQL

              sql.results
            end
          else
            ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
              sql = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<~SQL, repository_id: repository_id, table_name: table_name
                INSERT INTO repository_milestones_sequences
                  (repository_id, number, created_at, updated_at)
                VALUES
                  (:repository_id, (SELECT MAX(number) FROM `:table_name` where repository_id = :repository_id), NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                  number = (SELECT MAX(number) FROM `:table_name` where repository_id = :repository_id),
                  updated_at = NOW()
              SQL

              sql.results
            end
          end
        end
      end
    end
  end
end
