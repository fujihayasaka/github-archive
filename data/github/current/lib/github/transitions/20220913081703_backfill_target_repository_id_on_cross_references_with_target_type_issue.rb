# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"
require "ruby-progressbar"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220913081703_backfill_target_repository_id_on_cross_references_with_target_type_issue.rb --verbose | tee -a /tmp/backfill_target_repository_id_on_cross_references_with_target_type_issue_transition.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220913081703_backfill_target_repository_id_on_cross_references_with_target_type_issue.rb --verbose -w | tee -a /tmp/backfill_target_repository_id_on_cross_references_with_target_type_issue_transition.log
#
module GitHub
  module Transitions
    class BackfillTargetRepositoryIdOnCrossReferencesWithTargetTypeIssue < Transition
      include Divvy::Parallelizable

      READ_BATCH_SIZE = 10000
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 10000 : 1
      MAX_RETRY_COUNT = 8

      def after_initialize
        @start_id =
          @other_args[:start_id] ||
          readonly { ApplicationRecord::Domain::IssuesPullRequests.github_sql.value("SELECT MIN(id) FROM cross_references") || 0 }

        @end_id =
          @other_args[:end_id] ||
          readonly { ApplicationRecord::Domain::IssuesPullRequests.github_sql.value("SELECT MAX(id) FROM cross_references") || 0 }

        @progress_bar = ProgressBar.create(
          total: @end_id - @start_id + 1, # think IDs 1-11, that's 11 rows.
          format: "%c/%C | %w | %a (%E)",
          throttle_rate: 1,
          title: "Backfilling target_repository_ids on cross_references with target type 'Issue'",
          output: Rails.env.test? ? StringIO.new : STDERR)

        @iterator = readonly do
          ApplicationRecord::Domain::IssuesPullRequests.github_sql_batched_between(
            start: @start_id,
            finish: @end_id,
            batch_size: READ_BATCH_SIZE)
        end

        @iterator.add <<~SQL
          SELECT cross_references.id
          FROM cross_references
          WHERE cross_references.id BETWEEN :start AND :last
            AND cross_references.target_repository_id IS NULL
            AND cross_references.target_type = 'Issue'
        SQL
      end

      # Returns nothing.
      def perform
        @progress_bar.log "Starting transition #{self.class.to_s.underscore} - #{@end_id - @start_id + 1} cross_references rows."

        dispatch { |ids| process(ids) }

        @progress_bar.log "Finished transition #{self.class.to_s.underscore}"
      end

      def dispatch
        @iterator.batches.each do |rows|
          ids = rows.flatten
          next if ids.empty?

          yield ids

          # approximate approach to estimate progress.
          @progress_bar.progress = [@progress_bar.progress, ids.last - @start_id + 1].max
        end

        @progress_bar.finish
      end

      def process(ids)
        if dry_run?
          readonly do
            sql = ApplicationRecord::Domain::IssuesPullRequests.github_sql.run <<~SQL, ids: ids
              SELECT COUNT(*)
              FROM cross_references
              INNER JOIN issues ON cross_references.target_id = issues.id
              WHERE cross_references.id IN :ids
                AND cross_references.target_repository_id IS NULL
            SQL
          end
        else
          if WRITE_BATCH_SIZE == 1
            ids.each do |id|
              ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
                sql = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<~SQL, id: id
                  UPDATE cross_references
                  INNER JOIN issues ON cross_references.target_id = issues.id
                  SET cross_references.target_repository_id = issues.repository_id
                  WHERE cross_references.id = :id
                    AND cross_references.target_repository_id IS NULL
                SQL

                sql.results
              end
            end
          else
            ids.each_slice(WRITE_BATCH_SIZE) do |ids_slice|
              ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
                sql = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<~SQL, ids: ids_slice
                UPDATE cross_references
                INNER JOIN issues ON cross_references.target_id = issues.id
                SET cross_references.target_repository_id = issues.repository_id
                WHERE cross_references.id IN :ids
                  AND cross_references.target_repository_id IS NULL
                SQL

                sql.results
              end
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby your_script.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::BackfillTargetRepositoryIdOnCrossReferencesWithTargetTypeIssue.new(**options)
  master = Divvy::Master.new(transition, options[:workers], options[:verbose])
  master.run
end
