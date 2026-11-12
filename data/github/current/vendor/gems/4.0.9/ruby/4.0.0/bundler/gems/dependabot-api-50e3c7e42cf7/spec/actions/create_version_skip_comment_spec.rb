# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateVersionSkipComment do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:repo) { FactoryBot.create(:repo, github_id: 88071876) }
  let!(:pull_request) { FactoryBot.create(:pull_request, repo: repo) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:pr_comments_url) do
    github_repo_url + "/issues/#{pull_request.github_number}/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:github_comments) do
    fixture("github_responses/issue_comments_not_mentioned.json")
  end
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
    stub_request(:get, pr_comments_url + "?per_page=100").
      to_return(status: 200, body: github_comments, headers: json_header)
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: pull_request.repo,
                            event_source: anything).
      and_return(dummy_repo_synchronizer)
  end

  it "comments on the pull request" do
    action.run
    expect(WebMock).to have_requested(:post, pr_comments_url)
  end

  context "when the account is inactive" do
    before do
      installation_id = repo.account.current_installation_id
      repo.account.transition_to!(
        :inactive,
        installation_id: installation_id,
      )
    end

    it "does not comment on the pull request" do
      action.run
      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "when the PR has had a close comment before" do
    let(:github_comments) do
      fixture("github_responses/issue_comments_closed_before.json")
    end

    it "does not comment on the pull request" do
      action.run
      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "when the repo has been archived" do
    before do
      error = {
        errors: [
          { status: 403, title: "Repository was archived so is read-only" },
        ],
      }.to_json

      stub_request(:post, pr_comments_url).
        to_return(status: 403, body: error, headers: json_header)
    end

    it "quietly ignores the request" do
      expect { action.run }.not_to raise_error
    end
  end

  context "when the repo has been deleted" do
    before do
      stub_request(:post, pr_comments_url).
        to_return(status: 404, headers: json_header)
    end

    it "resyncs the repo state" do
      expect(dummy_repo_synchronizer).to receive(:run)

      expect { action.run }.not_to raise_error
    end
  end

  context "when the PR is for multiple dependencies" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        dependencies: [
          { name: "business", version: "2.0.0" },
          { name: "statesman", version: "1.8.0" },
        ],
      )
    end

    it "does not tell the user how to ignore major/minor versions" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).not_to include("@dependabot ignore") },
      )
    end
  end

  context "when the PR has a numeric version" do
    it "tells the user how to ignore major/minor versions" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).to include("@dependabot ignore") },
      )
    end
  end

  context "when the PR has a non-numeric version" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        dependencies: [{ name: "business", version: "~> 2.0" }],
      )
    end

    it "does not tell the user how to ignore major/minor versions" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).not_to include("@dependabot ignore") },
      )
    end
  end

  context "when the repo is using a config file" do
    before { repo.update!(config_file_path: ".github/dependabot.yml") }

    it "tells the user about ignoring update types" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).to include("with the desired `update_types`") },
      )
    end
  end

  context "when the repo is not using a config file" do
    it "tells the user about ignoring update types" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).not_to include("with the desired `update_types`") },
      )
    end
  end

  context "when the pull request is a grouped update" do
    before { pull_request.update!(grouped_update: true) }

    let(:comment_text) do
      "This pull request was built based on a group rule. " \
      "Closing it will not ignore any of these versions in future pull requests.\\n\\n" \
      "To ignore these dependencies, configure [ignore rules]"
    end

    it "tells the user about version not ignored on pull request closing" do
      action.run
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |r| expect(r.body).to include(comment_text) },
      )
    end
  end
end
