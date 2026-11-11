# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class DeleteDuplicatedIssues < Transition
      # Uncomment this if running this transition with Divvy
      # include Divvy::Parallelizable

      # #dotcom-db-migration-help is your friend, and can help code review
      # transitions before they're run to make sure they're being nice to our
      # database clusters. We're usually looking for a few things in transitions:
      #   1. Iterators: We want to query the database for records to change in batches
      #   2. Read-Only Replicas: If we're reading data to be changed, we want to do it on
      #      the read-only replicas to keep load off the primary.
      #   3. Throttle writes: We want to make sure we wrap any actual writes to the primary
      #      in a `throttle_with_retry` block, which should be called on the most specific
      #      `ApplicationRecord::*` class/subclass or object. This will make sure we don't
      #      overwhelm primary and cause replication lag.
      #   4. Efficient queries: We want to avoid massive table scans, so make sure your
      #      query has an index or is performant and safe without one.
      #
      #   For more information on all this, checkout the transition docs at
      #   https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/

      # It is recommended to add an ActiveRecord subclass (if applicable) to your transition for each table you need
      # inside the transition itself. You can then also copy all the code within those subclasses that the transition
      # needs into the subclass defined in the transition.
      #
      # This way the transition is self-contained and no change outside of it has any influence.
      #
      # ```
      # class ClassName < ApplicationRecord::Domain::DomainName
      #   self.table_name = :class_name
      #
      #   # Add any relevant attributes or class methods to the class inside the transition
      # end
      # ```
      class Issue < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issues
      end

      # Recommended batch size number, but you can modify for your use case
      #
      # Consider increasing *_BATCH_SIZE to decrease transition run time
      # and maintenance window for GHES instance. Replication lag isn't a
      # concern during GHES maintenance/upgrades.
      #
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      # attr_reader :iterator
      # attr_reader :total_updated
      # attr_reader :max_id

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        # The most common, and preferred, approach is to define your iterator
        # here using `BatchedBetween`. Prefer using a min_id with BatchedBetween
        # queries. Not doing so can lead to _very_ slow transition tests (https://github.com/github/github/pull/92565)
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::IssuesPullRequests.connection
            .select_value(Arel.sql("SELECT MIN(pull_request_id) FROM issues")) || 0
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::IssuesPullRequests.connection
            .select_value(Arel.sql("SELECT MAX(pull_request_id) FROM issues")) || 0
        end
        #
        # # github_sql_batched_between holds on to the current connection so we need to wrap it in a readonly block
        # # when instantiating it so that we read from replicas when we iterate over it.
        #
        @iterator = readonly do
          ApplicationRecord::Domain::IssuesPullRequests
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT pull_request_id, COUNT(pull_request_id) FROM issues
          WHERE pull_request_id BETWEEN :start AND :last
          GROUP BY pull_request_id
          HAVING COUNT(pull_request_id) > 1
        SQL
      end

      # Returns nothing.
      def perform
        GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
          process(rows)
        end
      end

      private

      def process(rows)
        # Note: When writing a transition, we must consider its execution environments: Dotcom and GHES.
        # In Dotcom, in order to avoid replication lag, we've determined that it's better to run single row updates,
        # and use Divvy to parallelize a transition when it's being run on Dotcom (especially for long-running transitions).
        # But in Enterprise, the opposite is true: because migrations are executed between version upgrades,
        # while the appliance is offline, we want to optimize for performance and run larger batches.
        # If you're writing a long running transition that also needs to in Enterprise mode, please consider
        # using a batch update and using a batch size of 1 for Dotcom but a larger batch size for Enterprise.
        #
        # For more information, please consult the documentation:
        # https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
        # If you're touching the database, please use the throttler to ensure
        # that this transition doesn't cause unnecessary replication delay:
        #
        # Example of using a batch update that works for both Dotcom and Enterprise environments:
        #
        rows.each_slice(write_batch_size) do |slice|
          ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            affected_issues = []
            slice.map do |row|
              readonly do
                pr_issues = ApplicationRecord::Domain::IssuesPullRequests.connection
                  .select_values(Arel.sql("SELECT id FROM issues WHERE pull_request_id = ? ORDER BY id", row[0]))

                first_issue = pr_issues.delete_at(0)
                log "pull_request_id: #{row[0]} - first associated issue id: #{first_issue} - issue count: #{row[1]}"
                affected_issues << pr_issues
              end
            end

            affected_issues.each do |issue_ids|
              run_batch_delete(issue_ids) unless issue_ids.empty?
            end
          end
        end
      end

      def run_batch_delete(issue_ids)
        log dry_run? ? "Would delete issue ids #{issue_ids}" : "Deleting issue ids #{issue_ids}"

        issues_to_be_deleted = Issue.where(id: issue_ids)
        issues_to_be_deleted.each do |issue|
          log "Deleting issue #{issue.inspect}"
          issue.delete unless dry_run?
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: delete_duplicated_issues.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |start_id|
      options[:start_id] = start_id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |end_id|
      options[:end_id] = end_id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |read_batch_size|
      options[:read_batch_size] = read_batch_size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |write_batch_size|
      options[:write_batch_size] = write_batch_size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |workers|
      options[:workers] = workers
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::DeleteDuplicatedIssues.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::DeleteDuplicatedIssues.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
