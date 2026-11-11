# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221026072622_clean_up_issue_events_for_transformed_orgs.rb --verbose | tee -a /tmp/clean_up_issue_events_for_transformed_orgs_dry_run.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221026072622_clean_up_issue_events_for_transformed_orgs.rb --verbose -w | tee -a /tmp/clean_up_issue_events_for_transformed_orgs_write_run.log
module GitHub
  module Transitions
    # This transition cleans up any 'review_request_removed' issue_events and their
    # associated issue_event_details where the subject was originally a User but has
    # since been transformed into an Organization.
    # See https://github.com/github/mEAO/issues/373 for details.
    class CleanUpIssueEventsForTransformedOrgs < Transition
      BATCH_SIZE = 10_000 # Big batches for sparse data.
      DELETE_BATCH_SIZE = GitHub.enterprise? ? 100 : 2

      attr_reader :iterator

      def after_initialize
        @total_deleted_issue_events = 0
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::IssuesPullRequests.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM issue_events")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::IssuesPullRequests.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM issue_events")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE

        readonly do
          @iterator = ApplicationRecord::Domain::IssuesPullRequests
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
          @iterator.add <<~SQL
            SELECT issue_events.id, issue_event_details.subject_id
            FROM issue_events
            INNER JOIN issue_event_details ON (
              issue_event_details.issue_event_id = issue_events.id
              AND issue_event_details.subject_type = "User"
            )
            WHERE issue_events.id BETWEEN :start AND :last
            AND issue_events.event = 'review_request_removed'
          SQL
        end
      end

      def perform
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        if verbose?
          if dry_run?
            log "Would have deleted #{@total_deleted_issue_events} issue_events (and their associated issue_event_details)"
          else
            log "Deleted #{@total_deleted_issue_events} issue_events (and their associated issue_event_details)"
          end
        end
      end

      private

      def process(rows)
        subject_ids = rows.map { |row| row[1] }
        org_ids = readonly do
          User.github_sql.values <<-SQL, ids: subject_ids
            SELECT id
            FROM users
            WHERE id IN :ids
            AND type = 'Organization'
          SQL
        end
        return unless org_ids.any?

        event_ids_to_delete = rows.map do |row|
          row[0] if org_ids.include?(row[1])
        end.compact

        if dry_run?
          @total_deleted_issue_events += event_ids_to_delete.size
          log "Would be removing issue_events with IDs: #{event_ids_to_delete}" if verbose?
          nil
        else
          log "Removing issue_events with IDs: #{event_ids_to_delete}" if verbose?
          event_ids_to_delete.each_slice(DELETE_BATCH_SIZE) do |slice|
            IssueEvent.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              @total_deleted_issue_events += run_batch_delete(slice)
            end
          end
        end
      end

      def run_batch_delete(ids)
        deleted_issue_events = T.let(0, Integer)

        ActiveRecord::Base.connected_to(role: :writing) do
          delete_issue_events = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<-SQL, ids: ids
            DELETE FROM issue_events
            WHERE issue_events.id IN :ids
          SQL
          delete_issue_events.run
          deleted_issue_events = T.let(delete_issue_events.affected_rows, Integer)

          delete_issue_event_details = ApplicationRecord::Domain::IssuesPullRequests.github_sql.new <<-SQL, ids: ids
            DELETE FROM issue_event_details
            WHERE issue_event_details.issue_event_id IN :ids
          SQL
          delete_issue_event_details.run
        end

        deleted_issue_events
      end
    end
  end
end

if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options]"

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

  transition = GitHub::Transitions::CleanUpIssueEventsForTransformedOrgs.new(**options)
  transition.run
end
