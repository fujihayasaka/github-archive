# frozen_string_literal: true

require "rails_helper"

RSpec.describe CancelActionsWorkflowRunJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(update_job, update_job.actions_workflow_run_id) }

  let(:update_job) { create(:update_job, :on_gh_actions) }
  let(:dummy_tester) { instance_double(CancelActionsWorkflowRun, run: nil) }

  before do
    allow(CancelActionsWorkflowRun).
      to receive(:new).
      with(update_job:, workflow_run_id: update_job.actions_workflow_run_id).
      and_return(dummy_tester)
  end

  it "delegates to CancelActionsWorkflowRun" do
    expect(dummy_tester).to receive(:run)
    job.perform_now
  end

  it "deletes a cached access token on Octokit::Unauthorized errors" do
    expect(GitHubHelpers).to receive(:delete_cached_access_token_for).
      with(account: update_job.repo.account)
    allow(dummy_tester).to receive(:run).and_raise(Octokit::Unauthorized)
    job.perform_now
  end

  described_class::RETRYABLE_ERRORS.each do |err_class|
    let(:error) do
      if err_class.is_a?(Octokit::Error)
        err_class.new({ headers: [] })
      else
        err_class.new
      end
    end

    it "retries #{err_class.name} errors" do
      allow(dummy_tester).to receive(:run).and_raise(error)
      expect { job.perform_now }.to enqueue_job(described_class)
    end
  end
end
