# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class RemoveDiscussionsLockedState < Transition
      include Divvy::Parallelizable

      # Recommended batch size number, but you can modify for your use case
      #
      # Consider increasing *_BATCH_SIZE to decrease transition run time
      # and maintenance window for GHES instance. Replication lag isn't a
      # concern during GHES maintenance/upgrades.
      #
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      OPEN_STATE_VALUE = 0
      LOCKED_STATE_VALUE = 3

      attr_reader :iterator
      attr_reader :total_updated

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Discussions.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM discussions")
        end

        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Discussions.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM discussions")
        end

        @total_updated = 0

        @iterator = readonly do
          ApplicationRecord::Domain::Discussions
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL, locked_state_value: LOCKED_STATE_VALUE
          -- id must go first for batched between to work properly
           SELECT id FROM discussions
           WHERE id BETWEEN :start AND :last
           AND state = :locked_state_value
        SQL
      end

      # Returns nothing.
      def perform
        dispatch { |rows| process(rows) }
      end

      def dispatch
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          yield rows
        end
      end

      private

      def process(rows)
        discussion_ids = rows.flatten
        locked_at_by_discussion_ids = load_locked_at_for(ids: discussion_ids)

        rows.each_slice(write_batch_size) do |slice|
          sliced_ids = slice.flatten

          log "Processing #{sliced_ids.join(", ")}" if verbose?
          @total_updated += run_batch_update(
            discussion_ids: sliced_ids,
            locked_at_by_discussion_ids: locked_at_by_discussion_ids,
          )
        end

        log "#{dry_run? ? "Would update" : "Updated"} #{total_updated} discussions" if verbose?
      end

      def load_locked_at_for(ids:)
        results = readonly do
          ApplicationRecord::Domain::Discussions.github_sql.new(<<~SQL, discussion_ids: ids).results
            SELECT
              discussion_id,
              MAX(created_at)
            FROM discussion_events
            WHERE discussion_id IN :discussion_ids AND event_type = 0
            GROUP BY discussion_id
          SQL
        end

        results.to_h
      end

      def run_batch_update(discussion_ids:, locked_at_by_discussion_ids:)
        return discussion_ids.size if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          # Set `locked_at` column
          Discussion.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            sql = ApplicationRecord::Domain::Discussions.github_sql.new "UPDATE discussions SET locked_at = CASE"
            discussion_ids.each do |id|
              locked_at = locked_at_by_discussion_ids[id] || Time.now
              sql.add <<~SQL, id: id, locked_at: locked_at
                WHEN id = :id THEN :locked_at
              SQL
            end

            # Change state from `locked` to `open`
            sql.add "END, state = CASE"
            discussion_ids.each do |id|
              sql.add <<~SQL, id: id, state: OPEN_STATE_VALUE
                WHEN id = :id THEN :state
              SQL
            end
            sql.add "END WHERE id IN :ids", ids: discussion_ids
            sql.run
            log "Updated state and locked_at for #{discussion_ids.join(", ")}" if verbose?
            sql.affected_rows
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

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::RemoveDiscussionsLockedState.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run

  transition = GitHub::Transitions::RemoveDiscussionsLockedState.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
