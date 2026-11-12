# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::DeleteAbandonedPendingPrUpdates do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:backlog_metric_key) do
    "scheduled_jobs.delete_abandoned_pending_pr_updates.backlog"
  end

  context "when the PR is old enough" do
    before do
      create(:pending_pull_request_update, created_at: 3.weeks.ago)
    end

    it "deletes the PR updates" do
      expect { job.perform_now }.to change(PendingPullRequestUpdate, :count).by(-1)
    end

    it "gauges the remaining backlog as 0" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 0)

      job.perform_now
    end
  end

  context "with a PendingPullRequestUpdate that was recently created" do
    before do
      create(:pending_pull_request_update, created_at: 1.week.ago)
    end

    it "doesn't delete the PR update" do
      expect { job.perform_now }.not_to change(PendingPullRequestUpdate, :count)
    end

    it "gauges the remaining backlog as 0" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 0)

      job.perform_now
    end
  end

  context "when a limit is set" do
    before do
      create_list(:pending_pull_request_update, 2, created_at: 3.weeks.ago)
    end

    it "deletes only the specified number of PendingPullRequestUpdates" do
      expect { job.perform_now(limit: 1) }.
        to change(PendingPullRequestUpdate, :count).from(2).to(1)
    end

    it "gauges the remaining backlog as 1" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 1)

      job.perform_now(limit: 1)
    end
  end
end
