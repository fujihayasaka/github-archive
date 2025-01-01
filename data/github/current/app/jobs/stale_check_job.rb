# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class StaleCheckJob < ApplicationJob
  queue_as :stale_check_runs

  # No retry_on because we're running again in 90 seconds.

  schedule interval: 90.seconds
  DURATION_SECONDS = 60

  BATCH_SIZE = 1000

  exempt_from_tenant_context_requirement

  # Ensure that only one maintenance pass is happening at a time in the unlikely event we run much longer than 60 seconds.
  # Ignore job arguments when generating the key.
  locked_by timeout: 2.minutes, key: ->(_job) { "key" }

  def perform
    # Temporarily pausing this job while we add an index and a perform a transition on this data
    # https://github.com/github/feature-management/issues/224#issuecomment-815262383
    # Tests have been also deleted until the ballast vitess migration finishes, see https://github.com/github/data-partitioning/issues/361
    return unless FeatureFlag.vexi.enabled?(:automatic_stale_checks, default: false)

    # Run for up to 60 seconds.
    start_time = Time.now
    end_at = start_time.to_f + DURATION_SECONDS

    Instrumentation.track_time("checks.stale.time_per_batch.dist.time") do
      CheckSuite.throttle do
        incomplete_suites = CheckSuite
          .incomplete_and_older_than_stale_threshold
          .annotate("cross-shard-query-exempted")
          .limit(BATCH_SIZE)

        GitHub.dogstats.gauge("checks.stale.batch_size", incomplete_suites.count)

        incomplete_suites.each do |check_suite|
          begin
            CheckSuite.throttle_writes do
              CheckRun.throttle_writes do
                check_suite.mark_stale!(start_time)
              end
            end
          rescue StandardError => err # rubocop:todo Lint/RescueException
            # Report failure but don't stop processing the batch.
            Failbot.report(err.with_redacting!)
          end
          break if Time.now.to_f >= end_at
        end
      end
    end
  end
end
