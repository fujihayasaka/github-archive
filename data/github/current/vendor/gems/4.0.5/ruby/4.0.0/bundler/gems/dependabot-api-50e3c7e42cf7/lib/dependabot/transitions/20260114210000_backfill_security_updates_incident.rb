# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

# Backfill security_updates_enabled for repos affected by the 2026-01-14 incident.
#
# During the incident window (~13 hours), Hydro messages for security updates
# enable/disable were failing due to a key rename in gh/gh (repository -> repo).
# This transition syncs the correct state from gh/gh for affected repos.
#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20260114210000_backfill_security_updates_incident.rb -v -n 100
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20260114210000_backfill_security_updates_incident.rb -v -w -n 12000
module Dependabot
  module Transitions
    class BackfillSecurityUpdatesIncident < Dependabot::Transition
      # Freno db cluster to throttle for writes.
      FRENO_CLUSTER = :dependabot

      # Path to the file containing affected repo IDs (one per line)
      # Generated from Kusto audit log query:
      #
      # database('hydro').audit_log_v2_audit_entry
      # | where timestamp between (datetime('2026-01-13 19:00:00') .. datetime('2026-01-14 08:00:00'))
      # | where action in ("repository_security_updates.enable", "repository_security_updates.disable")
      # | summarize arg_max(timestamp, action) by repo_id=tolong(extract_json("$.repo_id", document))
      # | where action == "repository_security_updates.enable" or action == "repository_security_updates.disable"
      # | project repo_id, timestamp
      #
      # These are repos where security updates were toggled during the incident window.
      # Total: 11,896 repos
      AFFECTED_REPO_IDS_FILE = File.expand_path("data/20260114_backfill_security_updates_incident_repo_ids.txt",
                                                __dir__)

      def self.affected_repo_ids
        @affected_repo_ids ||= File.readlines(AFFECTED_REPO_IDS_FILE).map(&:to_i).freeze
      end

      def after_initialize
        @backfill_count = 0
        @error_count = 0
        @backfill_limit = other_args[:backfill_limit]

        batch_size = [@backfill_limit, other_args[:batch_size]].min
        @iterator = target_repos_relation.in_batches(of: batch_size)
      end

      def perform
        estimated_backfill_count = [target_repos_relation.count, backfill_limit].min
        log "Backfilling security_updates_enabled for approx. #{estimated_backfill_count} repos..."
        log "Incident 3653: 2026-01-14 VulnerabilityUpdatesEnabledProcessor crash"

        iterator.each do |repos|
          break if backfill_count >= backfill_limit

          process(repos)
        end

        log "Done. Backfilled #{backfill_count} repos, #{error_count} errors."
      end

      private

      attr_reader :backfill_count, :backfill_limit, :iterator, :error_count

      def process(repos)
        batch_size = backfill_count + repos.size > backfill_limit ? backfill_limit - backfill_count : repos.size

        log "Processing batch of #{batch_size} repos..." if verbose?

        if dry_run?
          @backfill_count += batch_size
          return
        end

        Dependabot.freno_throttler.throttle(FRENO_CLUSTER) do
          repos.each do |repo|
            break if backfill_count >= backfill_limit

            sync_repo(repo)
          end
        end
      end

      def sync_repo(repo)
        repo_settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
        repo.update!(security_updates_enabled: repo_settings.automated_security_updates_enabled)
        @backfill_count += 1
      rescue StandardError => e
        @error_count += 1
        log "Error syncing repo #{repo.github_id}: #{e.message}" if verbose?
      end

      def target_repos_relation
        @target_repos_relation ||= Repo.where(github_id: self.class.affected_repo_ids)
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

    options.integer "-b",
                    "--batch-size",
                    "The number of repos to process at a time.",
                    default: 100

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(
    dry_run: !options[:write],
    batch_size: options[:batch_size],
    backfill_limit: options[:max_write_count]
  )

  transition = Dependabot::Transitions::BackfillSecurityUpdatesIncident.new(**options)
  transition.run
end
