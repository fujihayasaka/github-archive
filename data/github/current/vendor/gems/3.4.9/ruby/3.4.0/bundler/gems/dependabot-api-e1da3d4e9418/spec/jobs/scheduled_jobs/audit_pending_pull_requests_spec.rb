# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::AuditPendingPullRequests, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) { described_class.new }

  let(:expected_stagnant_log_message) do
    "PendingPullRequest over 3 hours old hasn't been created."
  end

  let(:expected_stagnant_metric) do
    "scheduled_jobs.audit_pending_pull_requests.stagnant"
  end

  before do
    allow(Dependabot::Logger).to receive(:info)
    allow(MetricsClient).to receive(:gauge)
  end

  context "with a recently created pending pull request" do
    let!(:pending_pull_request) { FactoryBot.create(:pending_pull_request) }

    it "doesn't log anything" do
      job.perform_now
      expect(Dependabot::Logger).not_to have_received(:info)
    end

    it "gauges the number of stagnant pending pull requests as 0" do
      job.perform_now

      expect(MetricsClient).
        to have_received(:gauge).with(expected_stagnant_metric, 0)
    end

    it "doesn't modify the pending pr" do
      job.perform_now

      expect(pending_pull_request.current_state(force_reload: true)).
        to eql("pending")
    end
  end

  context "with old pending pull requests" do
    let!(:pending_pull_request1) do
      travel_to(4.hours.ago) do
        FactoryBot.create(
          :pending_pull_request, state,
        )
      end
    end

    let!(:pending_pull_request2) do
      travel_to(4.hours.ago) do
        FactoryBot.create(
          :pending_pull_request, :pending,
        )
      end
    end

    context "when both are pending" do
      let(:state) { :pending }

      it "logs the jobs" do
        job.perform_now

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request1.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request1.id,
                 "gh.repo.id": pending_pull_request1.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request1.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request1.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request1.update_job.update_config.account.github_id,
               ))

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request2.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request2.id,
                 "gh.repo.id": pending_pull_request2.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request2.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request2.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request2.update_job.update_config.account.github_id,
               ))
      end

      it "gauges the number of stagnant jobs" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(expected_stagnant_metric, 2)
      end

      it "doesn't modify the pending prs" do
        job.perform_now

        expect(pending_pull_request1.current_state(force_reload: true)).
          to eql("pending")

        expect(pending_pull_request2.current_state(force_reload: true)).
          to eql("pending")
      end
    end

    context "when one has been created" do
      let(:state) { :created }

      it "logs only 1 jobs" do
        job.perform_now

        expect(Dependabot::Logger).
          not_to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request1.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request1.id,
                 "gh.repo.id": pending_pull_request1.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request1.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request1.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request1.update_job.update_config.account.github_id,
               ))

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request2.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request2.id,
                 "gh.repo.id": pending_pull_request2.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request2.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request2.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request2.update_job.update_config.account.github_id,
               ))
      end

      it "gauges the number of stagnant jobs" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(expected_stagnant_metric, 1)
      end
    end

    context "when one was created more than a day ago" do
      let!(:pending_pull_request3) do
        travel_to(25.hours.ago) do
          FactoryBot.create(
            :pending_pull_request, :pending,
          )
        end
      end

      let(:state) { :pending }

      it "gauges the number of stagnant jobs" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(expected_stagnant_metric, 3)
      end

      it "logs the jobs" do
        job.perform_now

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request1.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request1.id,
                 "gh.repo.id": pending_pull_request1.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request1.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request1.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request1.update_job.update_config.account.github_id,
               ))

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request2.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request2.id,
                 "gh.repo.id": pending_pull_request2.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request2.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request2.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request2.update_job.update_config.account.github_id,
               ))

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: expected_stagnant_log_message,
                 "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
                 "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request3.created_at,
                 "gh.dependabot_api.pending_pull_request.id": pending_pull_request3.id,
                 "gh.repo.id": pending_pull_request3.update_job.repo.github_id,
                 "gh.dependabot_api.update_job.id": pending_pull_request3.update_job.id,
                 "gh.dependabot_api.update_config.id": pending_pull_request3.update_job.update_config.id,
                 "gh.owner.id": pending_pull_request3.update_job.update_config.account.github_id,
               ))
      end

      it "abandons the day-old pending pr" do
        job.perform_now

        expect(pending_pull_request1.current_state(force_reload: true)).
          to eql("pending")

        expect(pending_pull_request2.current_state(force_reload: true)).
          to eql("pending")

        expect(pending_pull_request3.current_state(force_reload: true)).
          to eql("abandoned")
      end
    end
  end

  # This is a case that should never happen in the real world as PendingPullRequests aren't capable
  # of transitioning back into 'pending' from any other state.
  #
  # We test this as we have overriden Statesman's internal behaviour for querying rows in their initial
  # state as it doesn't perform well for our use-case.
  #
  # This provides a regression test in the event we ever do start transitioning pending PRs back
  # into their initial state elsewhere -or- Statesman's internals change
  context "with an old pending pull request which has a materialised starting 'pending' transition" do
    let!(:pending_pull_request) do
      travel_to(1.day.ago) do
        pending_pull_request = FactoryBot.create(
          :pending_pull_request, :pending,
        )

        PendingPullRequestTransition.create(
          pending_pull_request: pending_pull_request,
          most_recent: true,
          to_state: :pending,
          sort_key: 0
        )

        pending_pull_request
      end
    end

    it "logs and abandons the pending pr" do
      job.perform_now

      expect(MetricsClient).to have_received(:gauge).with(expected_stagnant_metric, 1)

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: expected_stagnant_log_message,
               "code.namespace": "ScheduledJobs::AuditPendingPullRequests",
               "gh.dependabot_api.pending_pull_request.created_at": pending_pull_request.created_at,
               "gh.dependabot_api.pending_pull_request.id": pending_pull_request.id,
               "gh.repo.id": pending_pull_request.update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": pending_pull_request.update_job.id,
               "gh.dependabot_api.update_config.id": pending_pull_request.update_job.update_config.id,
               "gh.owner.id": pending_pull_request.update_job.update_config.account.github_id,
             ))

      expect(pending_pull_request.current_state(force_reload: true)).
        to eql("abandoned")
    end
  end
end
