# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

# Remediate Proxima repos affected by incident 3653.
#
# Incident 3653: Hydro messages for security updates enable/disable were failing
# due to a key rename in gh/gh (repository -> repo). This transition handles both:
#   1. Repos that exist in dependabot-api → sync state via SynchronizeRepoState
#   2. Repos missing from dependabot-api → create via SetupAccountAndRepoWithGlobalAppJob
#
# STAMP DETECTION:
#   The stamp is automatically detected from the PROXIMA_STAMP environment variable
#   (set when running against a Proxima environment). Valid stamps:
#   prod-weu-01, prod-ae-01, prod-sdc-01, prod-cus-01, test-cnc-01, prod-jpw-01
#
# DATA FILE:
#   Expects a CSV file at: data/proxima_<stamp>_repo_data.csv
#   Format: repo_id,owner_id,tenant_id,tenant_slug (with header)
#
#   Generated using this Kusto query (run against each Proxima stamp's data warehouse):
#
#     database('hydro').audit_log_v2_audit_entry
#     | where timestamp between (datetime('2026-01-13 19:00:00') .. datetime('2026-01-14 08:00:00'))
#     | where action in ("repository_security_updates.enable", "repository_security_updates.disable")
#     | summarize arg_max(timestamp, action, document) by repo_id=tolong(extract_json("$.repo_id", document))
#     | extend org_id=tolong(extract_json("$.org_id", document)), user_id=tolong(extract_json("$.user_id", document))
#     | extend tenant_id = tostring(extract_json("$.business_id", document))
#     | extend tenant_slug = tostring(extract_json("$.business", document))
#     | project repo_id, owner_id=coalesce(org_id, user_id), tenant_id, tenant_slug
#
# To run in dry-run mode:
#   .transitions run <pr-url> prod-weu-01 20260115_proxima_incident_3653.rb -v -n 1000
#
# To run in write mode:
#   .transitions run <pr-url> prod-weu-01 20260115_proxima_incident_3653.rb -v -w -n 1000
#
module Dependabot
  module Transitions
    class ProximaIncident3653 < Dependabot::Transition
      # Event source for tracking this incident remediation in logs and metrics
      EVENT_SOURCE = "incident_3653_proxima"

      RepoData = Struct.new(:owner_id, :tenant_id, :tenant_slug, keyword_init: true)

      def stamp_name
        @stamp_name ||= begin
          stamp = Prius.get(:proxima_stamp)
          raise "PROXIMA_STAMP not set. Run this transition against a Proxima environment." if stamp.blank?

          stamp
        end
      end

      def stamp_name_underscored
        @stamp_name_underscored ||= stamp_name.tr("-", "_")
      end

      def data_file
        File.expand_path("data/proxima_#{stamp_name_underscored}_repo_data.csv", __dir__)
      end

      # rubocop:disable Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/CyclomaticComplexity
      def repo_data
        @repo_data ||= begin
          mapping = {}
          raise "Data file not found: #{data_file}" unless File.exist?(data_file)

          File.readlines(data_file).each do |line|
            next if line.strip.empty? || line.start_with?("repo_id")

            parts = line.strip.split(",")
            repo_id = parts[0].to_i
            owner_id = parts[1].to_i
            tenant_id = parts[2]&.strip
            tenant_slug = parts[3]&.strip
            next unless repo_id.positive? && owner_id.positive?
            next if tenant_id.blank? || tenant_slug.blank?

            mapping[repo_id] = RepoData.new(
              owner_id: owner_id,
              tenant_id: tenant_id,
              tenant_slug: tenant_slug
            )
          end
          mapping.freeze
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/CyclomaticComplexity

      def after_initialize
        @sync_count = 0
        @remediate_count = 0
        @skip_count = 0
        @error_count = 0
        @backfill_limit = other_args[:backfill_limit]
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def perform
        all_repo_ids = repo_data.keys
        existing_repo_ids = Repo.where(github_id: all_repo_ids).pluck(:github_id).to_set
        missing_repo_ids = all_repo_ids - existing_repo_ids.to_a

        log "Incident 3653 Proxima Remediation: #{stamp_name}"
        log "Found #{all_repo_ids.size} affected repos in CSV"
        log "  - #{existing_repo_ids.size} repos exist (will sync)"
        log "  - #{missing_repo_ids.size} repos missing (will create)"
        log "Will process up to #{backfill_limit} repos..."

        process_count = 0

        # First, sync existing repos
        all_repo_ids.each do |repo_id|
          break if process_count >= backfill_limit
          next unless existing_repo_ids.include?(repo_id)

          sync_repo(repo_id)
          process_count += 1
        end

        # Then, remediate missing repos
        missing_repo_ids.each do |repo_id|
          break if process_count >= backfill_limit

          remediate_repo(repo_id)
          process_count += 1
        end

        log "Done. Synced #{sync_count}, created #{remediate_count}, skipped #{skip_count}, errors #{error_count}."
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      attr_reader :sync_count, :remediate_count, :skip_count, :error_count, :backfill_limit

      def sync_repo(repo_id)
        repo = Repo.find_by(github_id: repo_id)
        return unless repo

        log "Syncing repo #{repo_id} (#{repo.name})..." if verbose?

        if dry_run?
          @sync_count += 1
          return
        end

        SynchronizeRepoState.new(repo: repo, event_source: EVENT_SOURCE).run
        @sync_count += 1
      rescue StandardError => e
        @error_count += 1
        log "Error syncing repo #{repo_id}: #{e.message}"
      end

      # rubocop:disable Metrics/MethodLength
      def remediate_repo(repo_id)
        data = repo_data[repo_id]

        unless data
          log "Skipping repo #{repo_id}: no data found" if verbose?
          @skip_count += 1
          return
        end

        log "Creating repo #{repo_id} (owner: #{data.owner_id}, tenant: #{data.tenant_slug})..." if verbose?

        if dry_run?
          @remediate_count += 1
          return
        end

        SetupAccountAndRepoWithGlobalAppJob.perform_later(
          account_github_id: data.owner_id,
          repo_github_id: repo_id,
          tenant_id: data.tenant_id,
          tenant_slug: data.tenant_slug,
          event_source: EVENT_SOURCE
        )
        @remediate_count += 1
      rescue StandardError => e
        @error_count += 1
        log "Error creating repo #{repo_id}: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end

if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.bool "-w", "--write", "Enable writes", default: false
    options.integer "-n", "--max-write-count", "Maximum writes", required: true
    options.bool "-v", "--verbose", "Verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write], backfill_limit: options[:max_write_count])

  transition = Dependabot::Transitions::ProximaIncident3653.new(**options)
  transition.run
end
