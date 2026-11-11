# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateComment do
  subject(:action) do
    described_class.new(pull_request: pull_request, comment_body: comment_body)
  end

  let(:repo) { create(:repo) }
  let(:pull_request) { create(:pull_request, repo: repo, github_number: 21) }
  let(:comment_body) { "Superseded by #18." }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{pull_request.repo.github_id}" }
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    stub_request(:post, repo_url + "/issues/21/comments")
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: pull_request.repo,
                            event_source: "action.create_comment").
      and_return(dummy_repo_synchronizer)
  end

  it "comments on the pull_request" do
    action.run

    expect(WebMock).
      to have_requested(:post, repo_url + "/issues/21/comments").
      with(body: { body: comment_body }.to_json)
  end

  context "with a stub PR" do
    let(:pull_request) { Stubs::PullRequest.new(repo: repo, github_number: 21) }

    it "comments on the pull_request" do
      action.run

      expect(WebMock).
        to have_requested(:post, repo_url + "/issues/21/comments").
        with(body: { body: comment_body }.to_json)
    end
  end

  context "with an inactive account" do
    before do
      pull_request.repo.account.transition_to!(
        :inactive,
        installation_id: pull_request.repo.account.current_installation_id,
      )
      stub_request(:post, repo_url + "/issues/21/comments").
        to_return(status: 401)
      login = pull_request.repo.account.github_login
      stub_request(:get, "#{github_url}users/#{login}/installation").
        to_return(status: 404)
    end

    it "doesn't raise" do
      expect(dummy_repo_synchronizer).to receive(:run)

      action.run

      expect(WebMock).
        to have_requested(:post, repo_url + "/issues/21/comments").
        with(body: { body: comment_body }.to_json)
    end
  end

  context "but the old pull_request is locked" do
    let(:locked) { fixture("github_responses/forbidden_locked.json") }

    before do
      stub_request(:post, repo_url + "/issues/21/comments").
        to_return(status: 403, body: locked, headers: json_header)
    end

    it "doesn't raise" do
      action.run

      expect(WebMock).
        to have_requested(:post, repo_url + "/issues/21/comments").
        with(body: { body: comment_body }.to_json)
    end
  end

  context "but the account has been shadow banned" do
    before do
      stub_request(:post, repo_url + "/issues/21/comments").
        to_return(status: 404)
      stub_request(:get, "https://github.com/hmarr").to_return(status: 404)
    end

    it "resyncs the repo state and does not raise" do
      expect(dummy_repo_synchronizer).to receive(:run)

      expect { action.run }.not_to raise_error
    end
  end

  context "but the repo has been archived" do
    let(:archived_response) { fixture("github_responses/forbidden_archived.json") }

    before do
      stub_request(:post, repo_url + "/issues/21/comments").
        to_return(status: 403, body: archived_response, headers: json_header)
    end

    it "resyncs the repo state and does not raise" do
      expect(dummy_repo_synchronizer).to receive(:run)

      expect { action.run }.not_to raise_error
    end
  end
end
