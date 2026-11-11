# frozen_string_literal: true

# Sometimes, errors happen when creating a PR from a PendingPullRequest. This
# may be because GitHub is down or because there is a bug in Dependabot Core.
#
# Additionally, sometimes Dependabot's queues might get very backed up, causing
# the CreatePullRequestJob not to be picked up by any worker.
module ScheduledJobs
  class AuditPendingPullRequests < ApplicationScheduledJob
    queue_as :default

    schedule interval: 1.day

    # After 1 day, any files related to a PendingPullRequest have expired in S3
    VIABILITY_PERIOD = 1.day
    # We delete UpdateJob logs after 14 days, after which the value of retaining
    # any PendingPullRequest is diminished for debugging purposes
    ABANDONED_TTL = 14.days

    def perform
      audit_stagnant_pending_prs
    end

    private

    def audit_stagnant_pending_prs
      stagnant_count = 0

      stagnant_pending_prs do |pending_pr|
        log(
          msg: "PendingPullRequest over 3 hours old hasn't been created.",
          pending_pr: pending_pr
        )
        stagnant_count += 1

        # Any PendingPullRequests still not created when the VIABILITY_PERIOD
        # has passed will no longer have files available in S3. At this point
        # they cannot be retried, so we abandon them.
        pending_pr.transition_to(:abandoned) if pending_pr.created_at < VIABILITY_PERIOD.ago
      end

      MetricsClient.gauge("scheduled_jobs.audit_pending_pull_requests.stagnant", stagnant_count)
    end

    def stagnant_pending_prs(&block)
      # It shouldn't take more than 3 hours for Dependabot to create a pending
      # pull request (we have exponential backoff on the creation job that
      # finishes after this time).
      #
      # We look at any rows still pending that were created in the last 2 days
      # since they should be abandoned after 1 day.
      #
      # This query can timeout over longer time ranges so we break it into smaller
      # one hour range queries to avoid timeouts.
      (2.days.ago.to_i..4.hours.ago.to_i).step(1.hour) do |i|
        start_at = Time.zone.at(i)
        end_at = start_at + 1.hour
        PendingPullRequest.
          in_state(:pending).
          where("#{PendingPullRequest.table_name}.created_at >= ? AND #{PendingPullRequest.table_name}.created_at < ?",
                start_at, end_at).find_each(&block)
      end
    end

    def log(msg:, pending_pr:)
      Dependabot::Logger.info(
        msg: msg,
        "code.namespace": self.class.to_s,
        "gh.dependabot_api.pending_pull_request.created_at": pending_pr.created_at,
        **pending_pr.telemetry_attributes,
      )
    end
  end
end
