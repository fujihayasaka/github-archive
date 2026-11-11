# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateReaction do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      comment_type: comment_type,
      comment_id: comment_id,
      reaction: "+1",
    )
  end

  let(:pull_request) { FactoryBot.create(:pull_request, github_number: 21) }
  let(:comment_id) { "123" }
  let(:comment_type) { "issue_comment" }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{pull_request.repo.github_id}/" }
  let(:reactions_url) { repo_url + "issues/comments/#{comment_id}/reactions" }
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:post, reactions_url)
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: pull_request.repo,
                            event_source: "action.create_reaction").
      and_return(dummy_repo_synchronizer)
  end

  it "acknowledges the request on GitHub" do
    action.run
    expect(WebMock).
      to have_requested(:post, reactions_url).
      with(body: { content: "+1" }.to_json)
  end

  context "with a review" do
    let(:comment_id) { "MDE3OlB1bGxSZXF1ZXN0UmV2aWV3MTQ2Mjk2ODc2" }
    let(:comment_type) { "review" }

    let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:post, github_graphql_endpoint).
        to_return(
          status: 200,
          body: fixture("github_responses/graphql_add_reaction.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "acknowledges the request on GitHub" do
      action.run
      expect(WebMock).
        to have_requested(:post, github_graphql_endpoint).
          with { |req| req.body.include?("THUMBS_UP") }
    end
  end

  context "but the old PR is locked" do
    let(:locked) { fixture("github_responses/forbidden_locked.json") }

    before do
      stub_request(:post, reactions_url).
        to_return(status: 403, body: locked, headers: json_header)
    end

    it "doesn't raise" do
      action.run

      expect(WebMock).
        to have_requested(:post, reactions_url).
        with(body: { content: "+1" }.to_json)
    end
  end

  context "but the installation no longer has access to the repository's issue comments" do
    let(:forbidden) { fixture("github_responses/forbidden_unavailable_to_integration.json") }
    let(:github_repo) { fixture("github_responses/repo.json") }

    before do
      pull_request.repo.update!(private: false)
      stub_request(:post, reactions_url).
        to_return(status: 403, body: forbidden, headers: json_header)
      stub_request(:get, "https://github.com/hmarr").
        to_return(status: 200, body: github_repo, headers: json_header)
    end

    it "resyncs the repo state" do
      expect(dummy_repo_synchronizer).to receive(:run)

      action.run
    end
  end
end
