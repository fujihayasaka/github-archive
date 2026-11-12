# frozen_string_literal: true

require "rails_helper"

RSpec.describe PullRequestCommits do
  subject(:pr_commits) { described_class.new(pull_request: pr) }

  let(:repo) { FactoryBot.create(:repo, :active, github_id: 123) }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/123" }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:pr) do
    FactoryBot.create(
      :pull_request,
      repo: repo,
      github_number: 1,
      head_commit_sha: "not-github",
      dependabot_commit_sha: "not-github",
    )
  end

  before do
    allow(GitHubHelpers).
      to receive(:access_token_for).
      and_return("token")
    stub_request(:get, repo_url + "/pulls/1/commits").
      to_return(status: 200, body: commits_body, headers: json_header)
  end

  context "for an edited PR with dependabot skipped commits" do
    let(:commits_body) do
      fixture("github_responses/commits_edited_skipped.json")
    end

    it "considers the pr as not edited" do
      expect(pr_commits.pr_has_been_edited?(head_sha: "not-commit-sha")).
        to eq(false)
    end
  end

  context "for a PR that has not been edited" do
    let(:commits_body) do
      fixture("github_responses/commits_unedited.json")
    end

    it "considers the pr as not edited" do
      expect(pr_commits.pr_has_been_edited?(head_sha: "not-commit-sha")).
        to eq(false)
    end
  end

  context "with unskipped commits" do
    let(:commits_body) { fixture("github_responses/commits_edited.json") }

    it "considers the PR as edited" do
      expect(pr_commits.pr_has_been_edited?(head_sha: "not-commit-sha")).
        to eq(true)
    end
  end

  context "when the head sha matches" do
    let(:commits_body) { fixture("github_responses/commits_edited.json") }

    it "considers the PR as not edited" do
      expect(pr_commits.pr_has_been_edited?(head_sha: "not-github")).
        to eq(false)
    end
  end
end
