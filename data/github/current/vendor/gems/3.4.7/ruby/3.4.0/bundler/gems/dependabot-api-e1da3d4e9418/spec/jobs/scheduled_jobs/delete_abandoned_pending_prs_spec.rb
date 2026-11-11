# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::DeleteAbandonedPendingPrs do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:backlog_metric_key) do
    "scheduled_jobs.delete_abandoned_pending_prs.backlog"
  end

  context "when the PR is old enough" do
    before do
      create(:pending_pull_request, created_at: 3.weeks.ago)
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

  context "with a PendingPullRequest that was recently created" do
    before do
      create(:pending_pull_request, created_at: 1.week.ago)
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

  context "when a limit is set" do
    before do
      create_list(:pending_pull_request, 2, created_at: 3.weeks.ago)
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
  end

  context "when deleting multiple PRs" do
    before do
      create_list(:pending_pull_request, 2, created_at: 3.weeks.ago).each do |pr|
        pr.transition_to!(:created)
      end
    end

    it "deletes the PRs and their associated transitions" do
      expect { job.perform_now }.
        to change(PendingPullRequestTransition, :count).by_at_least(-2)
    end
  end
end
