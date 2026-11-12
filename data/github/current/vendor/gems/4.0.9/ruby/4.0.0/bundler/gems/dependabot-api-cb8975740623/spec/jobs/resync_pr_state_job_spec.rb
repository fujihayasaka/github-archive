# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResyncPrStateJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }
  let(:repo) { pull_request.repo }
  let(:github_pr_data) { fixture("github_responses/pull_request_closed.json") }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:github_pr_url) do
    github_repo_url + "/pulls/#{pull_request.github_number}"
  end

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    stub_request(:get, github_pr_url).
      to_return(status: 200, body: github_pr_data, headers: json_header)
  end

  it "transitions the pull requests" do
    expect { job.perform_now }.
      to change { pull_request.reload.current_state }.
      from("up_to_date").to("closed")
  end

  context "when the PR was merged" do
    before { github_pr_data.gsub!(/"merged": false/, "\"merged\": true") }

    it "transitions the pull requests" do
      expect { job.perform_now }.
        to change { pull_request.reload.current_state }.
        from("up_to_date").to("merged")
    end
  end

  context "when the account is inactive" do
    before do
      installation_id = repo.account.current_installation_id
      repo.account.transition_to!(
        :inactive,
        installation_id: installation_id
      )
    end

    it "doesn't transition the pull request" do
      expect { job.perform_now }.
        not_to change { pull_request.reload.current_state }
    end
  end

  context "for a PR that can't be fetched" do
    before { stub_request(:get, github_pr_url).to_return(status: 404) }

    it "resyncs the repo" do
      result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
      )
      dummy_repo_synchronizer = double(run: result)
      expect(SynchronizeRepoState).
        to receive(:new).with(repo: repo,
                              event_source: "job.resync_pr_state").
        and_return(dummy_repo_synchronizer)
      expect(dummy_repo_synchronizer).to receive(:run)
      expect { job.perform_now }.
        not_to change { pull_request.reload.current_state }
    end
  end

  context "when a transition hits a race condition with a competing update" do
    it "when the competing update happens after validation it does not raise an error" do
      same_pr_different_instance = PullRequest.find(pull_request.id)

      # hook into the state machine creating a state transition to force
      # a competing update from another instance before the transition is created.
      storage_adapter = pull_request.state_machine.instance_variable_get(:@storage_adapter)
      allow(storage_adapter).to receive(:create).and_wrap_original do |m, *args|
        _, new_state, = args
        same_pr_different_instance.transition_to!(new_state)
        m.call(*args)
      end

      expect { job.perform_now }.not_to raise_error
    end

    it "when the competing update happens before validation it does not raise an error" do
      same_pr_different_instance = PullRequest.find(pull_request.id)

      # hook into Machine#transition_to! to create a competing update from another instance
      # before the transition is verified.
      allow(pull_request.state_machine).to receive(:transition_to!).and_wrap_original do |m, new_state|
        same_pr_different_instance.transition_to!(new_state)
        m.call(new_state)
      end

      expect { job.perform_now }.not_to raise_error
    end
  end
end
