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
    class ConvertMemexProjectViewTimelineLayoutsToRoadmap < Transition
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

      # Recommended batch size number, but you can modify for your use case
      #
      # Consider increasing *_BATCH_SIZE to decrease transition run time
      # and maintenance window for GHES instance. Replication lag isn't a
      # concern during GHES maintenance/upgrades.
      #
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_updated

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
          MemexProjectView.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM memex_project_views")
        end
        max_id = @other_args[:end_id] || readonly do
          MemexProjectView.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM memex_project_views")
        end

        @total_updated = 0

        # github_sql_batched_between holds on to the current connection so we need to wrap it in a readonly block
        # when instantiating it so that we read from replicas when we iterate over it.
        @iterator = readonly do
          MemexProjectView
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id, layout, layout_settings FROM memex_project_views
          WHERE id BETWEEN :start AND :last
          AND (layout = 3 OR layout_settings LIKE '%timeline%')
        SQL
      end

      # Returns nothing.
      def perform
        # A common approach is to only use the perform method to iterate through
        # your iterator, passing off the actual work to another method. Notice
        # that the actual iteration happens inside the `Readonly` model so
        # that we make sure we're hitting the read-only replicas and we can avoid
        # spiking replication lag.
        #
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        # For simpler read-only queries, use a readonly replica via:
        #
        # readonly do
        #   # ... your queries here
        # end
        #
        # For more information, please consult the documentation:
        # https://thehub.github.com/engineering/development-and-ops/dotcom/transitions/
        #
        # To include a final summary of the changes made:
        #
        verb = dry_run? ? "Would have updated" : "Updated"
        log("#{verb} #{total_updated} records")
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
        # https://thehub.github.com/engineering/development-and-ops/dotcom/transitions/
        # If you're touching the database, please use the throttler to ensure
        # that this transition doesn't cause unnecessary replication delay:
        #
        # Example of using a batch update that works for both Dotcom and Enterprise environments:

        rows.each_slice(write_batch_size) do |slice|
          MemexProjectView.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "doing something with #{slice.map { |item| item[0] }}" if verbose?
            @total_updated += run_batch_update(slice)
          end
        end
      end

      def run_batch_update(rows)
        return rows.size if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          sql = MemexProjectView.github_sql.new "UPDATE memex_project_views SET layout_settings = REPLACE(layout_settings, 'timeline', 'roadmap'), layout= CASE WHEN layout=3 THEN 4 ELSE layout END"
          sql.add " WHERE id IN :ids", ids: rows.map { |item| item[0] }
          sql.run
          sql.affected_rows
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
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

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Number of workers to use") do |workers|
      options[:workers] = workers
    end
  end.parse!

  options[:workers] ||= 1
  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::ConvertMemexProjectViewTimelineLayoutsToRoadmap.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::ConvertMemexProjectViewTimelineLayoutsToRoadmap.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
