# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20230201021645_backfill_repo_security_updates_enabled.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20230201021645_backfill_repo_security_updates_enabled.rb -v -w
module Dependabot
  module Transitions
    class BackfillRepoSecurityUpdatesEnabled < Dependabot::Transition
      # This Transition script is an alternative to running arbitary code in
      # production without code review, but remember there are some caveats
      # for Dependabot API at present:
      #
      # 1. We are using a k8s shell which is not very durable and may be
      #    displaced while the script is running.
      #    - Lock Dependabot API deploys while running a transition
      #    - Favour an approach that can be run in small batches to avoid this
      #    - Ensure your script is idempotent and safe to resume/re-run
      # 2. We do not have a readonly database connection at present, so make
      #    you test dry runs thoroughly!

      # Freno db cluster to throttle for writes.
      FRENO_CLUSTER = :dependabot

      # End time for phase 2 of paused rollout.
      ROLLOUT_PHASE2_END_AT = Time.zone.parse("2023-01-28").utc.end_of_day

      def after_initialize
        @backfill_count = 0
        @backfill_limit = other_args[:backfill_limit]

        batch_size = [other_args[:batch_size], @backfill_limit].min
        @iterator = target_repos_relation.in_batches(of: batch_size)
      end

      def perform
        estimated_backfill_count = [target_repos_relation.count, backfill_limit].min
        log "Backfilling security_updates_enabled for approx. #{estimated_backfill_count} repos..."

        iterator.each do |repos|
          break if backfill_count >= backfill_limit

          process(repos)
        end

        log "Done. Backfilled security_updates_enabled for #{backfill_count} repos."
      end

      private

      attr_reader :backfill_count, :backfill_limit, :iterator

      def process(repos)
        batch_size = backfill_count + repos.size > backfill_limit ? backfill_limit - backfill_count : repos.size

        log "Backfilling security_updates_enabled for batch of #{batch_size} repos..." if verbose?

        if dry_run?
          @backfill_count += batch_size
          return
        end

        Dependabot.freno_throttler.throttle(FRENO_CLUSTER) do
          repos.each do |repo|
            break if backfill_count >= backfill_limit

            repo_settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
            repo.update!(security_updates_enabled: repo_settings.automated_security_updates_enabled)
            @backfill_count += 1
          end
        end
      end

      def target_repos_relation
        Repo.
          where(security_updates_enabled: nil, paused_at: nil, will_pause_at: ...ROLLOUT_PHASE2_END_AT).
          joins(:update_configs).
          merge(UpdateConfig.active.where(update_schedule: "never"))
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
                    "The maximum number of writes allow.",
                    required: true

    options.integer "-b",
                    "--batch-size",
                    "The number of repos to process at a time.",
                    default: 1000

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

  transition = Dependabot::Transitions::BackfillRepoSecurityUpdatesEnabled.new(**options)
  transition.run
end
