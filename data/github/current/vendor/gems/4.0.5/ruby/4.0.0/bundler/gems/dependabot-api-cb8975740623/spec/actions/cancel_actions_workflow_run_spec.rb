# frozen_string_literal: true

require "rails_helper"

RSpec.describe CancelActionsWorkflowRun do
  subject(:action) { described_class.new(update_job:, workflow_run_id:) }

  let(:repo) { create(:repo, :active) }
  let(:update_job) { create(:update_job, :pending, :on_gh_actions, repo:) }
  let(:workflow_run_id) { update_job.actions_workflow_run_id }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:cancel_workflow_run_url) do
    github_url + "repositories/#{repo.github_id}/actions/runs/#{workflow_run_id}/cancel"
  end

  let(:repo_sync_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_sync) { instance_double(SynchronizeRepoState, run: repo_sync_result) }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    stub_request(:post, cancel_workflow_run_url).
      to_return(status: 202)

    allow(SynchronizeRepoState).
      to receive(:new).with(repo: repo, event_source: anything).
      and_return(dummy_repo_sync)

    allow(Dependabot::Logger).to receive(:info)
    allow(Dependabot::Logger).to receive(:error)
    allow(update_job).to receive(:increment_metric) if update_job.present?
  end

  context "with a valid update job and workflow run id" do
    it "cancels the workflow run" do
      expect(action.run).to be(true)

      expect(WebMock).to have_requested(:post, cancel_workflow_run_url)
    end

    it "logs success metrics" do
      action.run
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "success" })
    end
  end

  context "with a nil update job" do
    let(:update_job) { nil }
    let(:workflow_run_id) { 12345 }

    it "does not cancel a workflow run" do
      expect(action.run).to be(false)
      expect(WebMock).not_to have_requested(:post, cancel_workflow_run_url)
    end
  end

  context "with a non-actions update job" do
    let(:update_job) { create(:update_job, :pending, repo:) }

    it "does not cancel a workflow run" do
      expect(action.run).to be(false)
      expect(WebMock).not_to have_requested(:post, cancel_workflow_run_url)
    end
  end

  context "with an invalid workflow_run_id" do
    context "that is nil" do
      let(:workflow_run_id) { nil }

      it "does not cancel a workflow run" do
        expect(action.run).to be(false)
        expect(WebMock).not_to have_requested(:post, cancel_workflow_run_url)
      end
    end

    context "that is 0" do
      let(:workflow_run_id) { 0 }

      it "does not cancel a workflow run" do
        expect(action.run).to be(false)
        expect(WebMock).not_to have_requested(:post, cancel_workflow_run_url)
      end
    end
  end

  context "when the repo has been archived" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(
          status: 403,
          body: fixture("github_responses/forbidden_archived.json"),
          headers: json_header,
        )
    end

    it "resyncs the repo" do
      expect(action.run).to be(false)

      expect(dummy_repo_sync).to have_received(:run)
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
    end
  end

  context "for an access token that can't be fetched" do
    before do
      allow(GitHubHelpers).
        to receive(:access_token_for).
        and_call_original

      access_token_url = "#{github_url}app/global/access_tokens"
      stub_request(:post, access_token_url).to_return(status: 404)
    end

    it "resyncs the repo" do
      expect(action.run).to be(false)

      expect(dummy_repo_sync).to have_received(:run)
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
    end
  end

  context "when GitHub raises an unexpected, temporary 422" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(status: 422)
    end

    it "raises a helpful error" do
      expect { action.run }.to raise_error(/422/)

      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "error" })
    end
  end

  context "with bad credentials" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(
          status: 401,
          body: fixture("github_responses/bad_credentials.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises a helpful error" do
      expect { action.run }.to raise_error(/401/)
    end
  end

  context "with a not found response" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(
          status: 404,
          body: fixture("github_responses/not_found.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "returns false" do
      expect(action.run).to be(false)
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
    end
  end

  context "with a completed workflow run error" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(
          status: 409,
          body: fixture("github_responses/workflow_run/cancel_failed_completed.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "is gracefully handled" do
      expect(action.run).to be(false)
      expect(Dependabot::Logger).to have_received(:info)
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
    end
  end

  context "with an unqueued workflow re-run error" do
    before do
      stub_request(:post, cancel_workflow_run_url).
        to_return(
          status: 409,
          body: fixture("github_responses/workflow_run/cancel_failed_awaiting_rerun.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "is gracefully handled" do
      expect(action.run).to be(false)
      expect(Dependabot::Logger).to have_received(:info)
      expect(update_job).to have_received(:increment_metric).
        with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
    end
  end

  context "with an internal server error" do
    context "that is a known workflow run cancel failure" do
      before do
        stub_request(:post, cancel_workflow_run_url).
          to_return(
            status: 500,
            body: fixture("github_responses/workflow_run/cancel_failed_generic.json"),
            headers: { "Content-Type" => "application/json" },
          )
      end

      it "is gracefully handled" do
        expect(action.run).to be(false)
        expect(Dependabot::Logger).to have_received(:info)
        expect(update_job).to have_received(:increment_metric).
          with("cancel_actions_workflow_run.completed", tags: { result: "failure" })
      end
    end

    context "that is not a known workflow run cancel failure" do
      before do
        stub_request(:post, cancel_workflow_run_url).
          to_return(
            status: 500,
            body: fixture("github_responses/error_generic.json"),
            headers: { "Content-Type" => "application/json" },
          )
      end

      it "is gracefully handled" do
        expect { action.run }.to raise_error(/500/)
        expect(Dependabot::Logger).to have_received(:error)
        expect(update_job).to have_received(:increment_metric).
          with("cancel_actions_workflow_run.completed", tags: { result: "error" })
      end
    end
  end
end
