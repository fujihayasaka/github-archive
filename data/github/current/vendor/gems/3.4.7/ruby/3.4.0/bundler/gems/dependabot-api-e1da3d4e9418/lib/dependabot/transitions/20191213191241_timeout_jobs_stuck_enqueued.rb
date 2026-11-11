# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# To run this transition directly from an ops host:
#
#   $ gh-k8s-shell -n dependabot-api-production bash
#   # First, run the transition in dry-run mode
#   $ bundle exec ruby lib/dependabot/transitions/20191213191241_timeout_jobs_stuck_enqueued.rb -v
#   # Then, run the transition in regular mode
#   $ bundle exec ruby lib/dependabot/transitions/20191213191241_timeout_jobs_stuck_enqueued.rb -v -w
#
module Dependabot
  module Transitions
    class TimeoutJobsStuckEnqueued < Dependabot::Transition
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

      # Recommended batch size number, but you can modify for your use case
      BATCH_SIZE = 100
      INCIDENT_TIME = DateTime.parse("2019-11-13 00:00:00 UTC")
      AGE_RANGE = (INCIDENT_TIME..(INCIDENT_TIME + 1.month))

      attr_reader :iterator, :total_count, :updated_count

      def after_initialize
        @total_count = scope.count
        @updated_count = 0
        @iterator = scope.in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        log "Found '#{total_count}' jobs to cleanup"

        iterator.each do |rows|
          @updated_count += rows.count
          process(rows)
          log "Processed #{updated_count}/#{total_count}..."
        end
      end

      def process(rows)
        rows.each do |job|
          log "Transitioning Job ID '#{job.id}' to timed out" if verbose?

          next if dry_run?

          # An enqueued job must go via processing, since there are no triggers
          # on this tranistion in UpdateJobStateMachine, this is a harmless
          # step through to `timed_out`
          job.transition_to!(:processing)
          job.transition_to!(:timed_out)
        end
      end

      private

      def scope
        UpdateJob.in_state(:enqueued).where(most_recent_update_job_transition: {
                                              created_at: AGE_RANGE,
                                            })
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.on "-w",
               "--write",
               "Enable writes - this defaults to false for safety.",
               default: false

    options.on "-v",
               "--verbose",
               "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::TimeoutJobsStuckEnqueued.new(options)
  transition.run
end
