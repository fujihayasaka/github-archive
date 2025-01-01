# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221018194707_populate_push_type_and_pushed_at_data.rb --verbose | tee -a /tmp/populate_push_type_and_pushed_at_data.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221018194707_populate_push_type_and_pushed_at_data.rb --verbose -w | tee -a /tmp/populate_push_type_and_pushed_at_data.log
module GitHub
  module Transitions
    class PopulatePushTypeAndPushedAtData < Transition
      include Divvy::Parallelizable

      BATCH_READ_SIZE = GitHub.enterprise? ? 10000 : 100
      BATCH_UPDATE_SIZE = GitHub.enterprise? ? 1000 : 1

      attr_reader :total_processed_results_count, :total_updated_results_count

      def after_initialize
        @total_processed_results_count = 0
        @total_updated_results_count = 0

        min_id = @other_args[:start_id] || readonly { ApplicationRecord::Domain::RepositoriesPushes.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM pushes /* cross-shard-query-exempted */") }
        max_id = @other_args[:end_id] || readonly { ApplicationRecord::Domain::RepositoriesPushes.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM pushes /* cross-shard-query-exempted */") }

        # * The query has a condition with `:start` to constrain the start of the next iteration
        #   rows, e.g. `WHERE id BETWEEN :start AND :last`
        # * The query has a condition with `:last` to constrain the last seen id
        #   rows, e.g. `WHERE id BETWEEN :start AND :last`
        # * The query must return a value as the first item in each row which can be
        #   fed into the :last binding on each subsquent iteration. This value must be
        #   in ascending order.

        @iterator = ApplicationRecord::Domain::RepositoriesPushes.github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_read_size)
        @iterator.add <<-SQL
          SELECT id FROM pushes
          WHERE id BETWEEN :start AND :last
          ORDER BY id;
          /* cross-shard-query-exempted */
        SQL
      end

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        dispatch { |rows| process(rows) }

        log "Updated #{@total_updated_results_count} out of #{@total_processed_results_count} pushes"
        log "Finished #{self.class.to_s.underscore}."
      end

      def dispatch
        GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
          yield rows
        end
      end

      def process(rows)
        log "processing #{rows.count} rows" if verbose?
        return if rows.empty?

        push_ids = rows.map(&:first)
        log "processing pushes between ids #{push_ids.first} and #{push_ids.last}" if verbose?

        write_update(push_ids) unless dry_run?

        @total_processed_results_count += rows.size
        log "Updated #{@total_updated_results_count} out of #{@total_processed_results_count} pushes"
      end

      private

      def write_update(push_ids)
        push_ids.each_slice(batch_update_size).each do |push_ids_slice|
          ActiveRecord::Base.connected_to(role: :writing) do
            Push.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              sql = ApplicationRecord::Domain::RepositoriesPushes.github_sql.new(<<~SQL, push_ids: push_ids_slice)
                UPDATE pushes
                SET push_type = CASE
                WHEN pushes.forced = 1 AND pushes.push_type IS NULL THEN 1
                WHEN pushes.after = "#{GitHub::NULL_OID}" AND pushes.push_type IS NULL THEN 2
                WHEN pushes.before = "#{GitHub::NULL_OID}" AND pushes.push_type IS NULL THEN 3
                WHEN pushes.push_type IS NULL THEN 0
                ELSE push_type
                END,
                pushed_at = IFNULL(pushed_at, created_at)
                WHERE id IN :push_ids
                /* cross-shard-query-exempted */
              SQL

              sql.run

              @total_updated_results_count += sql.affected_rows
            end
          end
        end
      end

      def batch_read_size
        other_args[:batch_read_size] || BATCH_READ_SIZE
      end

      def batch_update_size
        other_args[:batch_update_size] || BATCH_UPDATE_SIZE
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

    opts.on("--batch-read-size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:batch_read_size] = size
    end

    opts.on("--batch-update-size SIZE", Integer, "Number of rows to update at a time") do |size|
      options[:batch_update_size] = size
    end

    opts.on("--no-rollback", "Do not write a rollback file; this may speed up your transition or dry run.") do
      options[:no_rollback] = true
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  # transition = GitHub::Transitions::PopulatePushTypeAndPushedAtData.new(**options)
  # transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  transition = GitHub::Transitions::PopulatePushTypeAndPushedAtData.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
