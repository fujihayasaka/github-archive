# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleReopenRequest do
  subject(:action) do
    described_class.new(pull_request: pull_request, requester: requester)
  end

  let(:requester) { "greysteil" }
  let!(:pull_request) do
    FactoryBot.create(:pull_request, :bump_test, github_number: 122)
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:refs_url) { repo_url + "git/refs" }
  let(:ref_url) { repo_url + "git/refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }
  let(:pr_body) { fixture("github_responses/pull_request_closed.json") }
  let(:not_found_body) { fixture("github_responses/not_found.json") }
  let(:pr_comments_url) do
    repo_url + "issues/#{pull_request.github_number}/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:dummy_pr_reopener) { instance_double(ReopenPullRequest, run: nil) }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
    allow(ReopenPullRequest).to receive(:new).and_return(dummy_pr_reopener)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
  end

  it "reopens the PR" do
    expect(dummy_pr_reopener).to receive(:run)
    action.run
  end

  context "with a pull request that is open" do
    let(:pr_body) { fixture("github_responses/pull_request_updating.json") }

    it "does not attempt to reopen the PR" do
      expect(dummy_pr_reopener).not_to receive(:run)
      action.run
    end
  end

  context "with a pull request that is open for this branch (not this one)" do
    before do
      allow(ReopenPullRequest).to receive(:new).and_call_original

      stub_request(:get, ref_url).
        to_return(status: 404, body: not_found_body, headers: json_header)

      stub_request(:post, refs_url).
        to_return(status: 200, body: pr_body, headers: json_header)

      stub_request(:patch, pr_url).
        to_return(
          status: 422,
          body: fixture("github_responses/validation_failed.json"),
          headers: json_header,
        )

      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "comments on the PR, explaining the problem" do
      action.run
      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "An open PR from this branch already exists, so this PR "\
                  "can't be re-opened.",
          }.to_json,
        )
    end
  end
end
