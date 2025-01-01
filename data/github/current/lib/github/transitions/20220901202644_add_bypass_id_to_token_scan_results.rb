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
#   $ gudo bin/safe-ruby lib/github/transitions/20220901202644_add_bypass_id_to_token_scan_results.rb --verbose | tee -a /tmp/add_bypass_id_to_token_scan_results.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220901202644_add_bypass_id_to_token_scan_results.rb --verbose -w | tee -a /tmp/add_bypass_id_to_token_scan_results.log
#
module GitHub
  module Transitions
    class AddBypassIdToTokenScanResults < Transition
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      UPDATE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      # attr_reader :iterator

      def after_initialize
        @prefix = dry_run? ? "dry run: " : ""
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM secret_scanning_push_protections_bypass;")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM secret_scanning_push_protections_bypass;")
        end
        @count_bypasses = readonly do
          ApplicationRecord::TokenScanningService.github_sql
            .value("SELECT COUNT(*) FROM secret_scanning_push_protections_bypass;")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE

        @iterator = readonly do
          ApplicationRecord::TokenScanningService
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT ssppb.id, signature, token_type, expire_at, created_at, os.owner_id FROM secret_scanning_push_protections_bypass ssppb
          JOIN owner_scopes os ON os.id = ssppb.owner_scope_id
          WHERE ssppb.id BETWEEN :start AND :last
        SQL

        log "initialization complete. found bypasses from #{min_id} to #{max_id}. #{@count_bypasses} total."
      end

      # Returns nothing.
      def perform
        total_affected = 0
        GitHub::SQL::Readonly.new(@iterator.batches).each_with_index do |rows, index|
          log "#{@prefix}starting to process batch #{index + 1}" if verbose?
          total_affected += process(rows)
        end
        log "#{@prefix}finished all batches. #{total_affected} rows affected in token_scan_results based on #{@count_bypasses} bypasses"
      end

      private

      def process(rows)
        slice_count_affected = 0
        log "#{@prefix}starting slice" if verbose?
        rows.each_slice(UPDATE_BATCH_SIZE) do |slice|
          ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "#{@prefix}updating token scan results with bypasses. processing bypasses from id #{slice.first[0]} to #{slice.last[0]} (#{slice.length} records)" if verbose?
            affected = run_batch_update slice
            log "#{@prefix}processed or found #{affected} matching rows in token_scan_results for batch" if verbose?
            slice_count_affected += affected
          end
        end
        log "#{@prefix}slice finished and affected #{slice_count_affected} records" if verbose?
        slice_count_affected
      end

      def run_batch_update(rows)
        readonly do
          if dry_run?
            matching_token_scan_results_found = 0
            rows.each do |(bypass_id, signature, token_type, bypass_expire_at, bypass_created_at, repository_id)|
              sql = ApplicationRecord::TokenScanningService.github_sql.new <<~SQL, bypass_id: bypass_id, signature: signature, token_type: token_type, bypass_expire_at: bypass_expire_at, bypass_created_at: bypass_created_at, repository_id: repository_id
                SELECT id
                FROM token_scan_results
                WHERE token_type = :token_type AND token_signature = :signature AND repository_id = :repository_id AND created_at > :bypass_created_at AND created_at < :bypass_expire_at AND bypass_id IS NULL
              SQL
              ## Should be impossible because there's a unique index on repository_id, token_type, token_signature (index_token_scan_results_on_repository_and_type_and_signature)
              ## so we should never see this log in the dry run
              if sql.results.length > 1
                log "dry run: somehow found more than one token scan result for bypass with id #{bypass_id}"
              end
              ## Possible to see this log in the dry run if a bypass was created, but the push never happened
              ## or if the bypass was created, push protection was turned off, and the push happened after the bypass expired
              if sql.results.length == 0
                log "dry run: found no token scan result for bypass with id #{bypass_id}"
              end
              matching_token_scan_results_found += sql.results.length
            end
            return matching_token_scan_results_found
          end
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          rows_updated = 0
          rows.each do |(bypass_id, signature, token_type, bypass_expire_at, bypass_created_at, repository_id)|
            sql = ApplicationRecord::TokenScanningService.github_sql.new "UPDATE token_scan_results"
            sql.add <<~SQL, bypass_id: bypass_id, signature: signature, token_type: token_type, bypass_expire_at: bypass_expire_at, bypass_created_at: bypass_created_at, repository_id: repository_id
              SET bypass_id = :bypass_id
              WHERE token_type = :token_type AND token_signature = :signature AND repository_id = :repository_id AND created_at > :bypass_created_at AND created_at < :bypass_expire_at AND bypass_id IS NULL
            SQL
            sql.run
            rows_updated += sql.affected_rows
          end
          return rows_updated
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

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::AddBypassIdToTokenScanResults.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::AddBypassIdToTokenScanResults.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
