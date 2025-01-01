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
#   $ gudo bin/safe-ruby lib/github/transitions/20220901140001_seed_audit_token_scan_results.rb --verbose | tee -a /tmp/seed_audit_token_scan_results.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220901140001_seed_audit_token_scan_results.rb --verbose -w | tee -a /tmp/seed_audit_token_scan_results.log
#
module GitHub
  module Transitions
    class SeedAuditTokenScanResults < Transition
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      UPDATE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      # attr_reader :iterator

      def after_initialize
        @prefix = dry_run? ? "dry run: " : ""
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM token_scan_results")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM token_scan_results")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE

        @iterator = readonly do
          ApplicationRecord::TokenScanningService
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT tsr.id, tsr.created_at, atsr.id FROM token_scan_results tsr
          LEFT JOIN audit_token_scan_results atsr ON atsr.token_scan_result_id = tsr.id
          WHERE tsr.id BETWEEN :start AND :last
          AND tsr.resolution != 4
          AND tsr.resolution IS NOT NULL
          AND atsr.id IS NULL
        SQL
      end

      def perform
        total_inserted = 0
        GitHub::SQL::Readonly.new(@iterator.batches).each_with_index do |rows, idx|
          log "#{@prefix}starting batch #{idx + 1}"
          inserts = process(rows)
          log "#{@prefix}finished batch #{idx + 1}. #{inserts} inserted"
          total_inserted += inserts
        end
        log "#{@prefix}finished all batches and inserted #{total_inserted} audit records"
      end

      private

      def process(rows)
        total_inserted = 0
        update_batch_size = @other_args[:update_batch_size] || UPDATE_BATCH_SIZE
        rows.each_slice(update_batch_size) do |slice|
          ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            inserts = run_batch_update slice
            log "#{@prefix}inserted #{inserts} in slice of batch" if verbose?
            total_inserted += inserts
          end
        end
        total_inserted
      end

      def run_batch_update(rows)
        if dry_run?
          return rows.length
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          sql = ApplicationRecord::TokenScanningService.github_sql.new "INSERT INTO audit_token_scan_results (token_scan_result_id, active_from, resolved, first_location_id, has_valid_locations, resolution_comment) VALUES"
          rows.each_with_index do |(id, created_at), idx|
            end_character = idx == rows.length - 1 ? ";" : ","
            sql.add <<~SQL, id: id, created_at: created_at
              (:id, :created_at, false, NULL, false, NULL)#{end_character}
            SQL
          end
          sql.run
          inserts = sql.affected_rows
          return inserts
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

    opts.on("--update_batch_size SIZE", Integer, "Number of rows to insert at a time") do |size|
      options[:update_batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::SeedAuditTokenScanResults.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::SeedAuditTokenScanResults.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
