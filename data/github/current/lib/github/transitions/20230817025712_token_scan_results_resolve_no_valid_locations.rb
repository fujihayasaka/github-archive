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
    class TokenScanResultsResolveNoValidLocations < Transition
      # Uncomment this if running this transition with Divvy
      # include Divvy::Parallelizable

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_updated
      attr_reader :max_id
      attr_reader :system_user_id

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        @prefix = dry_run? ? "dry run: " : ""
        min_id = @other_args[:start_id] || 0
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::TokenScanningService.connection
            .select_value(Arel.sql("SELECT COALESCE(MAX(id), 0) FROM token_scan_results where has_valid_locations = 0 AND resolved = 0;"))
        end

        login = GitHub.enterprise? ? "github-enterprise" : "github"
        gh_user = User.where(login: login).first
        @system_user_id = 0
        if gh_user.present?
          @system_user_id = gh_user.id
        end

        @iterator = readonly do
          ApplicationRecord::TokenScanningService.github_sql_batched(start: min_id, limit: read_batch_size)
        end

        @iterator.add <<-SQL, max_id: max_id
          SELECT id
          FROM token_scan_results
          WHERE has_valid_locations = 0
          AND resolved = 0
          AND id > :last
          AND id <= :max_id
          ORDER BY id ASC
          LIMIT :limit
        SQL
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
        rows.each_slice(write_batch_size) do |slice|
          TokenScanResult.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "updating resolution status for #{slice[0]} thru #{slice[-1]}" if verbose?
            @total_updated += run_batch_update(slice)
            log "Did something through id #{slice.last[0]}. Still need to set resolution up to id #{max_id.to_i}" if verbose?
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
        ids = rows.map { |row| row[0] }
        now = Time.now.utc
        update_sql = Arel.sql("UPDATE token_scan_results SET resolution = 8, resolved = 1, ")
        update_sql += Arel.sql("resolved_at = :resolved_at, resolver_id = :resolver_id, updated_at = :resolved_at WHERE id IN (:ids)",
          ids: ids,
          resolved_at: now,
          resolver_id: @system_user_id)

        results = ApplicationRecord::TokenScanningService.connection.select_rows(Arel.sql("SELECT id, resolution, resolver_id, resolved_at, resolved, first_location_id, has_valid_locations, resolution_comment, validity FROM token_scan_results WHERE id IN (:ids)", ids: ids))
        audit_sql = Arel.sql("INSERT INTO audit_token_scan_results (token_scan_result_id, active_from, resolution, resolver_id, resolved_at, resolved, first_location_id, has_valid_locations, resolution_comment, validity) VALUES")
        results.each_with_index do |(result_id, resolution, resolver_id, resolved_at, resolved, first_location_id, has_valid_locations, resolution_comment, validity), idx|
          end_character = idx == rows.length - 1 ? ";" : ","
          audit_sql += Arel.sql("(:result_id, :active_from, :resolution, :resolver_id, :resolved_at, :resolved, :first_location_id, :has_valid_locations, :resolution_comment, :validity)#{end_character}",
            result_id: result_id,
            active_from: now,
            resolution: resolution,
            resolver_id: resolver_id,
            resolved_at: resolved_at,
            resolved: resolved,
            first_location_id: first_location_id,
            has_valid_locations: has_valid_locations,
            resolution_comment: resolution_comment,
            validity: validity)
        end
        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::TokenScanningService.transaction do
            ApplicationRecord::TokenScanningService.connection.update(update_sql)
            ApplicationRecord::TokenScanningService.connection.insert(audit_sql)
          end
        end
        ids.size
      end
    end
  end
end

# Run as a single process if this script is run directly
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

  transition = GitHub::Transitions::TokenScanResultsResolveNoValidLocations.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::TokenScanResultsResolveNoValidLocations.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
