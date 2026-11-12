# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

# Remediate repos that were never created during the 2026-01-14 incident.
#
# During the incident window (~13 hours), Hydro messages for security updates
# enable/disable were failing due to a key rename in gh/gh (repository -> repo).
# For repos that didn't exist in dependabot-api, this means Dependabot was never
# installed. This transition uses RemediateAccountAndRepoActivation to create
# the missing account/repo records and trigger config file detection.
#
# This is a follow-up to 20260114210000_backfill_security_updates_incident.rb
# which fixed existing repos but couldn't handle repos that were never created.
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260114220000_remediate_missing_repos_incident.rb -v -n 1000
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260114220000_remediate_missing_repos_incident.rb -v -w -n 1000
#
module Dependabot
  module Transitions
    class RemediateMissingReposIncident < Dependabot::Transition
      # Path to the CSV file containing repo_id,owner_id mappings
      # Generated from Kusto query:
      #
      # database('hydro').audit_log_v2_audit_entry
      # | where timestamp between (datetime('2026-01-13 19:00:00') .. datetime('2026-01-14 08:00:00'))
      # | where action in ("repository_security_updates.enable", "repository_security_updates.disable")
      # | summarize arg_max(timestamp, action, document) by repo_id=tolong(extract_json("$.repo_id", document))
      # | extend org_id=tolong(extract_json("$.org_id", document)), user_id=tolong(extract_json("$.user_id", document))
      # | project repo_id, owner_id=coalesce(org_id, user_id)
      #
      REPO_OWNER_MAPPING_FILE = File.expand_path("data/repo_owner_mapping.csv", __dir__)

      EVENT_SOURCE = "incident_3653_backfill"

      def self.repo_owner_mapping
        @repo_owner_mapping ||= begin
          mapping = {}
          File.readlines(REPO_OWNER_MAPPING_FILE).drop(1).each do |line|
            repo_id, owner_id = line.strip.split(",").map(&:to_i)
            mapping[repo_id] = owner_id if repo_id.positive? && owner_id.positive?
          end
          mapping.freeze
        end
      end

      def after_initialize
        @remediate_count = 0
        @skip_count = 0
        @error_count = 0
        @backfill_limit = other_args[:backfill_limit]
      end

      def perform
        missing_repo_ids = compute_missing_repo_ids
        estimated_count = [missing_repo_ids.size, backfill_limit].min

        log "Incident 3653: 2026-01-14 VulnerabilityUpdatesEnabledProcessor crash"
        log "Found #{missing_repo_ids.size} repos missing from dependabot-api"
        log "Will remediate up to #{estimated_count} repos..."

        missing_repo_ids.each do |repo_id|
          break if remediate_count >= backfill_limit

          remediate_repo(repo_id)
        end

        log "Done. Remediated #{remediate_count} repos, skipped #{skip_count}, #{error_count} errors."
      end

      private

      attr_reader :remediate_count, :skip_count, :error_count, :backfill_limit

      def compute_missing_repo_ids
        all_repo_ids = self.class.repo_owner_mapping.keys
        existing_repo_ids = Repo.where(github_id: all_repo_ids).pluck(:github_id)
        all_repo_ids - existing_repo_ids
      end

      def remediate_repo(repo_id)
        owner_id = self.class.repo_owner_mapping[repo_id]

        unless owner_id
          log "Skipping repo #{repo_id}: no owner_id found" if verbose?
          @skip_count += 1
          return
        end

        log "Remediating repo #{repo_id} (owner: #{owner_id})..." if verbose?

        if dry_run?
          @remediate_count += 1
          return
        end

        RemediateAccountAndRepoActivation.new(
          github_repo_id: repo_id,
          github_account_id: owner_id,
          event_source: EVENT_SOURCE
        ).run
        @remediate_count += 1
      rescue StandardError => e
        @error_count += 1
        log "Error remediating repo #{repo_id}: #{e.message}" if verbose?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.bool "-w",
                 "--write",
                 "Enable writes - this defaults to false for safety.",
                 default: false

    options.integer "-n",
                    "--max-write-count",
                    "The maximum number of writes allowed.",
                    required: true

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(
    dry_run: !options[:write],
    backfill_limit: options[:max_write_count]
  )

  transition = Dependabot::Transitions::RemediateMissingReposIncident.new(**options)
  transition.run
end
