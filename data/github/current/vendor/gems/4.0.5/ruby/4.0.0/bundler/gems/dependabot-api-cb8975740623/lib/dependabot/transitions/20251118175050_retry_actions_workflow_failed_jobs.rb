# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# Transitions are orchestrated by the GitHub transitions service and are run
# via chatops:
#
#   .transitions run <pr-url> <environment> <arguments>
#
# A pull request is required to run a transition, so the first step is to
# create one for the transition files.
#
# To run a transition in a particular stamp, specify the stamp as the
# <environment>, e.g., prod-weu-01. To run a transition in all stamps,
# specify * as the <environment>.
#
# Before running a transition you should lock dependabot-api deployments.
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20251118175050_retry_actions_workflow_failed_jobs.rb -v
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20251118175050_retry_actions_workflow_failed_jobs.rb -v -w
#
# Once the transition is complete, merge the pull request.
#
module Dependabot
  module Transitions
    class RetryActionsWorkflowFailedJobs < Dependabot::Transition
      # Transitions provide an alternative to running arbitrary code in
      # production without code review.
      #
      # When designing a transition, favor an approach that can be run in small
      # batches and ensure your script is idempotent and safe to resume/re-run.
      #
      # Database connections default to writing, so be sure to test dry runs
      # thoroughly.

      # Recommended batch size number, but you can modify for your use case
      BATCH_SIZE = 100

      # Process jobs in smaller created_at windows to avoid large-range scans
      WINDOW_DURATION = 30.minutes

      # Time range for jobs to retry
      # These jobs failed during a specific incident window on 2025-11-17
      START_TIME = Time.parse("2025-11-17 00:00:00 UTC")
      END_TIME = Time.parse("2025-11-17 19:00:00 UTC")

      # Error types to retry
      ERROR_TYPES = %w(actions_workflow_image actions_workflow_updater).freeze

      attr_reader :total_count, :retried_count

      def after_initialize
        @total_count = windowed_scopes.sum(&:count)
        @retried_count = 0
        log "Found '#{total_count}' jobs to retry"
      end

      # Returns nothing.
      def perform
        windowed_scopes.each do |window_scope|
          window_scope.in_batches(of: BATCH_SIZE) do |rows|
            process(rows)
          end
        end
        log "Retried #{retried_count}/#{total_count} jobs"
      end

      def process(rows) # rubocop:disable Metrics/PerceivedComplexity
        rows.each do |job|
          next unless job.security?
          next unless target_error?(job)

          # Skip jobs if there's a newer update run after the incident window
          next if job.update_config.last_update_run&.created_at.to_i > END_TIME.to_i

          log "Retrying Job ID '#{job.id}'" if verbose?

          unless dry_run?
            job.retry!
            @retried_count += 1
          end
        end
        log "Processed #{retried_count}/#{total_count}..." unless dry_run?
      end

      private

      def scope(range = START_TIME..END_TIME)
        UpdateJob.where(created_at: range).
          where(command: :security)
      end

      def windowed_scopes
        time_window_ranges.map { |range| scope(range) }
      end

      def time_window_ranges
        ranges = []
        window_start = START_TIME

        while window_start <= END_TIME
          window_end = [window_start + WINDOW_DURATION, END_TIME].min
          range = window_end == END_TIME ? (window_start..window_end) : (window_start...window_end)
          ranges << range
          break if window_end == END_TIME

          window_start = window_end
        end

        ranges
      end

      def target_error?(job)
        job.update_job_errors.exists?(error_type: ERROR_TYPES)
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
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::RetryActionsWorkflowFailedJobs.new(**options)
  transition.run
end
