# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

# Resync accounts that have broken cron schedules.
#
# Some active cron-based update configs have a valid cron expression but
# next_enqueue_at is NULL, meaning they will never be enqueued. This transition
# finds accounts with at least one such broken config and resyncs them via
# Stafftools::ResyncAccountJob so that next_enqueue_at gets recalculated.
#
# The affected configs match:
#   update_schedule = 'cron'
#   AND update_schedule_cron_expression IS NOT NULL
#   AND next_enqueue_at IS NULL
#   AND repos.paused_at IS NULL
#   AND update_configs.current_state IN ('active', 'rate_limited')
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260316_resync_broken_cron_schedules.rb -v -n 1000
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260316_resync_broken_cron_schedules.rb -v -w -n 1000
#
module Dependabot
  module Transitions
    class ResyncBrokenCronSchedules < Dependabot::Transition
      def after_initialize
        @resync_count = 0
        @skip_count = 0
        @error_count = 0
        @backfill_limit = other_args[:backfill_limit]
      end

      def perform
        account_ids = broken_cron_account_ids

        log "Resync broken cron schedules"
        log "Will resync #{account_ids.size} accounts (limit: #{backfill_limit})..."

        account_ids.each do |account_id|
          resync_account(account_id)
        end

        log "Done. Resynced #{resync_count} accounts, skipped #{skip_count}, #{error_count} errors."
      end

      private

      attr_reader :resync_count, :skip_count, :error_count, :backfill_limit

      def broken_cron_account_ids
        UpdateConfig.active.
          joins(:repo).
          where(update_schedule: "cron").
          where.not(update_schedule_cron_expression: nil).
          where(next_enqueue_at: nil).
          where(Repo.table_name => { paused_at: nil }).
          limit(backfill_limit).
          distinct.
          pluck("#{Repo.table_name}.account_id")
      end

      def resync_account(account_id)
        account = Account.find_by(id: account_id)

        unless account
          log "Skipping account #{account_id}: not found" if verbose?
          @skip_count += 1
          return
        end

        log "Resyncing account #{account_id} (#{account.github_login})..." if verbose?

        if dry_run?
          @resync_count += 1
          return
        end

        Stafftools::ResyncAccountJob.perform_later(account: account)
        @resync_count += 1
      rescue StandardError => e
        @error_count += 1
        log "Error resyncing account #{account_id}: #{e.message}"
      end
    end
  end
end

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

  transition = Dependabot::Transitions::ResyncBrokenCronSchedules.new(**options)
  transition.run
end
