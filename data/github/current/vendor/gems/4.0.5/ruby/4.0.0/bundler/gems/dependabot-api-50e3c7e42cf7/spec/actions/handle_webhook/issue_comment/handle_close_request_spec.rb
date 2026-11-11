# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleCloseRequest do
  subject(:action) do
    described_class.new(pull_request: pull_request, requester: requester)
  end

  let(:requester) { "greysteil" }
  let(:pr_comments_url) do
    repo_url + "issues/#{pull_request.github_number}/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:github_comments) do
    fixture("github_responses/issue_comments_not_mentioned.json")
  end
  let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }
  let!(:pull_request) do
    FactoryBot.create(:pull_request, :bump_test, github_number: 122)
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:get, pr_comments_url + "?per_page=100").
      to_return(status: 200, body: github_comments, headers: json_header)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
  end

  it "closes the PR" do
    expect(dummy_pr_closer).to receive(:run)
    action.run
  end

  it "comments on the PR" do
    action.run
    expect(WebMock).
      to(
        have_requested(:post, pr_comments_url).
        with { |req| expect(req.body).to include("about this release") },
      )
  end

  it "does not create an ignore_condition" do
    expect { action.run }.not_to change(IgnoreCondition, :count)
  end

  context "when the PR is already closed" do
    let(:pr_body) { fixture("github_responses/pull_request_closed.json") }

    it "doesn't close the PR" do
      expect(dummy_pr_closer).not_to receive(:run)
      action.run
    end

    it "doesn't comment on the PR" do
      action.run
      expect(WebMock).not_to(have_requested(:post, pr_comments_url))
    end
  end
end
