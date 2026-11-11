# frozen_string_literal: true

# Sometimes, after an UpdateJob is enqueued, it is never picked up or
# acknowledged. This could be because of an infrastructure issue or because there is a bug
# in the updater that caused it not to be transitioned.
#
# Additionally, sometimes Dependabot's job processing might get very backed up, causing
# the UpdateJob not to be picked up for a long time.
#
# This will treat any UpdateJob that was enqueued over MAX_WAIT time ago as
# having become stagnant and will re-enqueue it. The UpdateJobStateMachine
# grants sufficient idempotence to tolerate potential duplicates
#
# In the event a job remains stagnant longer than VIABILITY_PERIOD after it
# was created, we consider it abandoned. In this scenario, it is unlikely
# the Repository state makes retrying viable.
#
# In the case of jobs requested via the UI, we immediately abandon them
# if they have become stagnant as GitHub will already reflect the job as having
# failed and it is likely a user will have retried before the MAX_WAIT period
# has elapsed.
#
module ScheduledJobs
  class AuditEnqueuedUpdateJobs < ApplicationScheduledJob
    queue_as :default

    schedule interval: 1.hour

    MAX_WAIT = 1.day
    SELF_HOSTED_VIABILITY_PERIOD_IN_HOURS = 24
    VIABILITY_PERIOD = 3.days

    def perform # rubocop:disable Metrics/MethodLength
      MetricsClient.gauge("scheduled_jobs.audit_enqueued_update_jobs.stagnant",
                          stagnant_update_jobs.count)

      return unless stagnant_update_jobs.exists?

      stagnant_update_jobs.find_each do |job|
        Dependabot::Logger.info(
          msg: "Job is over a day old and hasn't started processing.",
          "code.namespace": "ScheduledJobs::AuditEnqueuedUpdateJobs",
          "gh.dependabot_api.update_job.created_at": job.created_at,
          "gh.dependabot_api.update_job.trigger_type": job.trigger_type,
          **job.telemetry_attributes,
        )

        if viable?(job)
          MetricsClient.increment("scheduled_jobs.audit_enqueued_update_jobs.viable")
          job.transition_to!(:pending)
          PrioritizedJobs::StartUpdateJob.perform_later(job)
        elsif stale_self_hosted_job?(job)
          abandon_stale_self_hosted_job(job)
        else
          MetricsClient.increment("scheduled_jobs.audit_enqueued_update_jobs.abandoned")
          job.transition_to!(:abandoned)
        end
      end
    end

    private

    def viable?(job)
      return false if job.manual?
      return false if stale_self_hosted_job?(job)

      job.created_at > VIABILITY_PERIOD.ago
    end

    def stale_self_hosted_job?(job)
      job.self_hosted? && job.created_at < SELF_HOSTED_VIABILITY_PERIOD_IN_HOURS.hours.ago
    end

    def abandon_stale_self_hosted_job(job)
      job.update_job_errors.create(
        error_type: "self_hosted_runner_unavailable",
        error_details: {
          message: <<~MESSAGE.squish,
            No self-hosted runner was available to execute this job for more than
            #{SELF_HOSTED_VIABILITY_PERIOD_IN_HOURS} hours.
          MESSAGE
        }
      )

      job.transition_to!(:abandoned)
    end

    def stagnant_update_jobs
      # It shouldn't take more than a day for an update job to start processing
      # (at which point the job is marked as "processing").
      age_range = 10.years.ago..MAX_WAIT.ago

      UpdateJob.
        in_state(:enqueued).
        where(most_recent_update_job_transition: { created_at: age_range })
    end
  end
end
