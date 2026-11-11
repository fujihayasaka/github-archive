# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221004151956_backfill_secret_location_content_type.rb --verbose | tee -a /tmp/backfill_secret_location_content_type.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221004151956_backfill_secret_location_content_type.rb --verbose -w | tee -a /tmp/backfill_secret_location_content_type.log
module GitHub
  module Transitions
    class BackfillSecretLocationContentType < Transition
      # Uncomment this if running this transition with Divvy
      # include Divvy::Parallelizable

      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      UPDATE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      attr_reader :iterator
      attr_reader :rollback_filename
      attr_reader :total_updated

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM token_scan_result_locations_v2 WHERE content_type = 0")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM token_scan_result_locations_v2 WHERE content_type = 0")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE
        @total_updated = 0
        @iterator = ApplicationRecord::TokenScanningService
          .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id FROM token_scan_result_locations_v2
          WHERE id BETWEEN :start AND :last
          AND content_type = 0
        SQL

        log "Initialization complete. Found locations from #{min_id} to #{max_id}."
      end

      # Returns nothing.
      def perform
        @total_updated = 0
        GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
          process(rows)
        end

        verb = dry_run? ? "Would have updated" : "Updated"
        log("#{verb} #{@total_updated} records")
      end

      private

      def process(rows)
        update_batch_size = @other_args[:update_batch_size] || UPDATE_BATCH_SIZE
        rows.each_slice(update_batch_size) do |slice|
          ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "Updating content type on #{slice.length} records from id #{slice.first[0]} to #{slice.last[0]}" if verbose?
            @total_updated += run_batch_update(slice)
          end
        end
      end

      def run_batch_update(rows)
        return rows.size if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          sql = ApplicationRecord::TokenScanningService.github_sql.new "UPDATE token_scan_result_locations_v2 SET content_type = 1"
          sql.add "WHERE id IN :ids", ids: rows.map { |item| item[0] }
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

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("--update_batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:update_batch_size] = size
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

  transition = GitHub::Transitions::BackfillSecretLocationContentType.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::BackfillSecretLocationContentType.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
