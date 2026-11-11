# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class RemoveOldGroupedBoardViews < Transition
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_updated
      attr_reader :max_id

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
          ApplicationRecord::Domain::Memexes.connection
            .select_value(Arel.sql("SELECT COALESCE(MIN(id), 0) FROM memex_project_views"))
        end
        @max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Memexes.connection
            .select_value(Arel.sql("SELECT COALESCE(MAX(id), 0) FROM memex_project_views"))
        end
        log "Starting transition from id #{min_id} to #{max_id}" if verbose?

        @total_updated = 0

        # github_sql_batched_between holds on to the current connection so we need to wrap it in a readonly block
        # when instantiating it so that we read from replicas when we iterate over it.
        @iterator = readonly do
          ApplicationRecord::Domain::Memexes
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          SELECT id FROM memex_project_views
          WHERE id BETWEEN :start AND :last
          AND layout = 1
          AND JSON_LENGTH(group_by) > 0
        SQL
      end

      # Returns nothing.
      def perform
        # The actual iteration happens inside the `Readonly` model so
        # that we make sure we're hitting the read-only replicas and we can avoid
        # spiking replication lag.
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        verb = dry_run? ? "Would have updated" : "Updated"
        log("#{verb} #{total_updated} records")
      end

      private

      def process(rows)
        rows.each_slice(write_batch_size) do |slice|
          MemexProjectView.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "Removing groupBy with #{slice.map { |item| item[0] }}" if verbose?
            @total_updated += run_batch_update(slice)
            log "Removed groupBy through id #{slice.last[0]}. Still need to do something up to id #{max_id.to_i}" if verbose?
          end
        end
      end

      def run_batch_update(rows)
        if verbose?
          verb = dry_run? ? "Would update" : "Updating"
          first_id = rows.first[0]
          last_id = rows.last[0]
          if first_id == last_id
            log("#{verb} row #{first_id}...")
          else
            log("#{verb} rows #{first_id} - #{last_id}...")
          end
        end

        return rows.size if dry_run?

        # Update any board views with a group_by set to have an empty group_by array
        sql = Arel.sql("UPDATE memex_project_views SET group_by = '[]' WHERE id IN (:ids)", ids: rows.map { |row| row[0] })
        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::Domain::Memexes.connection.update(sql)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby lib/github/transitions/20230713181949_remove_old_grouped_board_views.rb [options]"

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
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::RemoveOldGroupedBoardViews.new(**options)
  transition.run
end
