# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20210610135251_resync_default_schedules.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20210610135251_resync_default_schedules.rb -v -w
#
module Dependabot
  module Transitions
    class ResyncDefaultSchedules < Dependabot::Transition
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

      OLD_DEFAULT_UPDATE_SCHEDULE_TIME_OF_DAY = "05:00"

      attr_reader :limit, :offset, :rollback

      def after_initialize
        @limit = @other_args.fetch(:limit)
        @offset = @other_args.fetch(:offset)
        @rollback = @other_args.fetch(:rollback)
      end

      # Returns nothing.
      def perform
        scope.each do |uc|
          repo = uc.repo
          account = repo.account
          github_id = repo.github_id

          log "resync config for #{account.github_id} - #{github_id}" if verbose?
          next if dry_run?

          # Prefer Stafftools::ResyncRepoJob to reprocess quietly
          Stafftools::ResyncRepoJob.perform_later(account: account, github_id: github_id)
        end
      end

      private

      def scope
        configs = UpdateConfig.scheduled.active
        # limit to repos using the old time when rolling out, to avoid triggering on every repo
        # trigger on every repo when rolling back, since we don't know what time configs were shifted to
        unless rollback
          configs = configs.
                    where(update_schedule_time_of_day: OLD_DEFAULT_UPDATE_SCHEDULE_TIME_OF_DAY)
        end

        configs.
          limit(limit).
          offset(offset).
          select("DISTINCT repo_id")
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

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"

    options.integer "--limit",
                    "Limits the number of records",
                    default: nil

    options.integer "--offset",
                    "Offsets the number of records",
                    default: 0

    options.bool "--rollback",
                 "Trigger on every repo, to revert to the old default schedule after reverting flag",
                 default: false
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::ResyncDefaultSchedules.new(options)
  transition.run
end
