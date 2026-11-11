# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::DeleteCreatedPendingPrs, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:backlog_metric_key) do
    "scheduled_jobs.delete_created_pending_prs.backlog"
  end

  context "with a PendingPullRequest whose update job is still processing" do
    let!(:update_job) { FactoryBot.create(:update_job, :processing) }
    let!(:pending_pull_request) do
      FactoryBot.create(:pending_pull_request, :created, update_job: update_job)
    end

    it "doesn't delete the PR" do
      expect { job.perform_now }.not_to change(PendingPullRequest, :count)
    end

    it "gauges the remaining backlog as 0" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 0)

      job.perform_now
    end
  end

  context "with a PendingPullRequest whose update job is processed" do
    let!(:update_job) { FactoryBot.create(:update_job, :processed) }
    let!(:pending_pull_request) do
      FactoryBot.create(:pending_pull_request, :created, update_job: update_job)
    end

    it "deletes the PR" do
      expect { job.perform_now }.to change(PendingPullRequest, :count).by(-1)
    end

    it "gauges the remaining backlog as 0" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 0)

      job.perform_now
    end
  end

  context "with a pending PendingPullRequest whose update job is processed" do
    let!(:update_job) { FactoryBot.create(:update_job, :processed) }
    let!(:pending_pull_request) do
      FactoryBot.create(:pending_pull_request, :pending, update_job: update_job)
    end

    it "doesn't deletes the PR" do
      expect { job.perform_now }.not_to change(PendingPullRequest, :count)
    end

    it "gauges the remaining backlog as 0" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 0)

      job.perform_now
    end
  end

  context "when a limit is set" do
    let!(:processed_update_job1) { FactoryBot.create(:update_job, :processed) }
    let!(:pending_pull_request1) do
      FactoryBot.create(:pending_pull_request,
                        :created,
                        update_job: processed_update_job1)
    end

    let!(:processed_update_job2) { FactoryBot.create(:update_job, :processed) }
    let!(:pending_pull_request2) do
      FactoryBot.create(:pending_pull_request,
                        :created,
                        update_job: processed_update_job2)
    end

    it "deletes only the specified number of PendingPullRequests " do
      expect { job.perform_now(limit: 1) }.
        to change(PendingPullRequest, :count).from(2).to(1)
    end

    it "gauges the remaining backlog as 1" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 1)

      job.perform_now(limit: 1)
    end

    context "with a PendingPullRequest whose update job is still processing" do
      let!(:processing_update_job) do
        FactoryBot.create(:update_job, :processing)
      end

      let!(:pending_pull_request) do
        FactoryBot.create(:pending_pull_request,
                          :created,
                          update_job: processing_update_job)
      end

      it "deletes only the specified number of complete PendingPullRequests " do
        expect { job.perform_now(limit: 1) }.
          to change(PendingPullRequest, :count).from(3).to(2)
      end

      it "gauges the remaining backlog as 1" do
        expect(MetricsClient).
          to receive(:gauge).with(backlog_metric_key, 1)

        job.perform_now(limit: 1)
      end
    end
  end
end
