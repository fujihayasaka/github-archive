# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergePullRequest do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/88632334/" }
  let(:branch_url) { repo_url + "git/refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_url) { repo_url + "pulls/18" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:merged_pr_body) { fixture("github_responses/merge_pull_request.json") }
  let(:open_prs_for_branch_url) do
    "#{repo_url}pulls?head=hmarr:bump_webmock_to_3.0.1&state=open"
  end

  let(:repo) { FactoryBot.create(:repo, github_id: 88632334) }
  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      repo: repo,
      github_number: 18,
      merge_requested: merge_requested,
    )
  end
  let(:merge_requested) { false }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:put, pr_url + "/merge").
      with(body: { merge_method: "merge", commit_message: "" }.to_json).
      to_return(status: 200, body: merged_pr_body, headers: json_header)
    stub_request(:get, open_prs_for_branch_url).
      to_return(status: 200, body: "[]", headers: json_header)
    stub_request(:delete, branch_url).
      to_return(status: 204, headers: json_header)
  end

  it "merges the PR on GitHub" do
    action.run

    expect(WebMock).
      to have_requested(:put, pr_url + "/merge").
      with(body: { merge_method: "merge", commit_message: "" }.to_json)
  end

  it "deletes the branch on GitHub" do
    action.run
    expect(WebMock).to have_requested(:delete, branch_url)
  end

  context "when the PR is updating (as a race)" do
    before do
      pull_request.transition_to!(:updating)
    end

    context "and require_up_to_date has been set to true" do
      subject(:action) do
        described_class.new(
          pull_request: pull_request,
          require_up_to_date: true,
        )
      end

      it "does not attempt to merge the PR" do
        expect(pull_request.current_state).to eq("updating")
        action.run
        expect(pull_request.reload.current_state).to eq("updating")
        expect(WebMock).not_to have_requested(:put, pr_url + "/merge")
        expect(WebMock).not_to have_requested(:delete, branch_url)
      end
    end
  end

  context "when other open PRs exist" do
    before do
      stub_request(:get, open_prs_for_branch_url).
        to_return(status: 200, body: "[{}]", headers: json_header)
    end

    it "does not delete the branch on GitHub" do
      action.run
      expect(WebMock).not_to have_requested(:delete, branch_url)
    end

    it "includes a tenant header when requesting open PRs", :proxima do
      action.run

      expect(WebMock).to have_requested(:get, open_prs_for_branch_url).
        with(headers: { "X-GitHub-Tenant" => repo.account.tenant.slug })
    end
  end

  context "when the account doesn't want merge commits" do
    before do
      repo.account.update!(create_merge_commits: false)
      stub_request(:put, pr_url + "/merge").
        with(body: { merge_method: "rebase", commit_message: "" }.to_json).
        to_return(status: 200, body: merged_pr_body, headers: json_header)
    end

    it "merges the commit with no-ff" do
      action.run
      expect(WebMock).
        to have_requested(:put, pr_url + "/merge").
        with(body: { merge_method: "rebase", commit_message: "" }.to_json)
    end
  end

  context "when the user has requested a squash and merge" do
    before do
      pull_request.update!(squash_requested: true)
      stub_request(:put, pr_url + "/merge").
        with(body: { merge_method: "squash", commit_message: "" }.to_json).
        to_return(status: 200, body: merged_pr_body, headers: json_header)
    end

    it "merges the commit with squash" do
      action.run
      expect(WebMock).
        to have_requested(:put, pr_url + "/merge").
        with(body: { merge_method: "squash", commit_message: "" }.to_json)
    end
  end

  context "when the PR is not mergeable" do
    context "because it is dirty" do
      let(:pr_body) { fixture("github_responses/pull_request_dirty.json") }

      it "does not attempt to merge the PR" do
        action.run
        expect(WebMock).not_to have_requested(:put, pr_url + "/merge")
        expect(WebMock).not_to have_requested(:delete, branch_url)
        expect(pull_request.reload.current_state).
          to eq("up_to_date")
      end
    end

    context "because it is behind" do
      let(:pr_body) { fixture("github_responses/pull_request_behind.json") }

      it "does not attempt to merge the PR" do
        action.run
        expect(WebMock).not_to have_requested(:put, pr_url + "/merge")
        expect(WebMock).not_to have_requested(:delete, branch_url)
      end
    end
  end

  context "when merging the PR fails (on GitHub)" do
    let(:message) do
      "At least 1 approving review is required by reviewers with write access"
    end

    before do
      message_json = { "message" => message }.to_json
      stub_request(:put, pr_url + "/merge").
        with(body: { merge_method: "merge", commit_message: "" }.to_json).
        to_return(status: 405, body: message_json, headers: json_header)
    end

    it "raises a MergeNotPossible error" do
      expect(pull_request.reload.current_state).
        to eq("up_to_date")
      expect { action.run }.
        to raise_error(MergePullRequest::MergeNotPossible)
      expect(pull_request.reload.current_state).
        to eq("up_to_date")
    end

    context "when other open PRs exist and fails due to routine errors" do
      before do
        stub_request(:get, open_prs_for_branch_url).
          to_return(status: 200, body: "[]", headers: json_header)
      end

      let(:message) { "Pull Request is not mergeable" }

      it "does not delete the branch on GitHub" do
        action.run
        expect(WebMock).not_to have_requested(:delete, branch_url)
      end
    end

    context "and the failure was because we can't push to the branch" do
      let(:message) { "You're not authorized to push to this branch." }

      it "raises a MergeNotPossible error" do
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
      end
    end

    context "and the failure was because not all commits are signed" do
      let(:message) { "Commits must have valid signatures." }

      it "raises a MergeNotPossible error" do
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
      end
    end

    context "and the failure was because of a repository rule violation" do
      let(:message) { "Repository rule violations found\n\nAnything at all" }

      it "raises a MergeNotPossible error" do
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
      end
    end

    context "and the failure was because the repo requires using the merge queue" do
      let(:message) { "Changes must be made through the merge queue" }

      it "raises a MergeNotPossible error" do
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
      end
    end

    context "and the failure was something else" do
      let(:message) { "Solar flare detected" }

      it "raises the original error and sets the PR back to the original state" do
        expect(pull_request.reload.current_state).
          to eq("up_to_date")

        expect { action.run }.
          to raise_error(Octokit::MethodNotAllowed)

        expect(pull_request.reload.current_state).
          to eq("up_to_date")
      end
    end

    context "and the failure was because a forbidden file has been edited" do
      before do
        message_json = { "message" => "a message" }.to_json
        stub_request(:put, pr_url + "/merge").
          with(body: { merge_method: "merge", commit_message: "" }.to_json).
          to_return(status: 403, body: message_json, headers: json_header)
        stub_request(:get, pr_url + "/files").
          to_return(status: 200, body: pr_files, headers: json_header)
      end

      let(:pr_files) do
        fixture("github_responses/pull_request_files_workflow.json")
      end

      it "raises a MergeNotPossible error" do
        expect(pull_request.reload.current_state).
          to eq("up_to_date")
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
        expect(pull_request.reload.current_state).
          to eq("up_to_date")
      end

      context "when other open PRs exist" do
        before do
          stub_request(:get, open_prs_for_branch_url).
            to_return(status: 200, body: "[{}]", headers: json_header)
        end

        it "does not delete the branch on GitHub" do
          expect { action.run }.
            to raise_error(MergePullRequest::MergeNotPossible)
          expect(WebMock).not_to have_requested(:delete, branch_url)
        end
      end

      context "for an unknown reason" do
        let(:pr_files) do
          fixture("github_responses/pull_request_files.json")
        end

        it "raises a MergeNotPossible error" do
          expect { action.run }.to raise_error(Octokit::Forbidden)
        end
      end
    end

    context "but the failure was because the branch needed rebasing" do
      let(:message) do
        "Base branch was modified. Review and try the merge again."
      end

      it "does not raise" do
        expect { action.run }.not_to raise_error
      end
    end

    context "but the failure was because the PR is already in the merge queue" do
      let(:message) { "Pull Request is in the merge queue" }

      it "does not raise" do
        expect { action.run }.not_to raise_error
      end
    end

    context "but the failure was because the PR is already being merged" do
      let(:message) do
        "Merge already in progress"
      end

      it "does not raise" do
        expect { action.run }.not_to raise_error
      end
    end

    context "and merge commits are not allowed" do
      let(:message) { "Merge commits are not allowed on this repository." }

      before do
        stub_request(:put, pr_url + "/merge").
          with(body: { merge_method: "rebase", commit_message: "" }.to_json).
          to_return(status: 200, body: merged_pr_body, headers: json_header)
      end

      it "merges the commit with no-ff" do
        expect { action.run }.
          to change { Account.find(repo.account_id).create_merge_commits }.
          from(true).to(false)
        expect(WebMock).
          to have_requested(:put, pr_url + "/merge").
          with(body: { merge_method: "rebase", commit_message: "" }.to_json)
      end
    end

    context "and branch protection rules dis-allow merges" do
      let(:message) { "This branch must not contain merge commits." }

      before do
        stub_request(:put, pr_url + "/merge").
          with(body: { merge_method: "rebase", commit_message: "" }.to_json).
          to_return(status: 200, body: merged_pr_body, headers: json_header)
      end

      it "merges the commit with no-ff" do
        expect { action.run }.
          to change { Account.find(repo.account_id).create_merge_commits }.
          from(true).to(false)
        expect(WebMock).
          to have_requested(:put, pr_url + "/merge").
          with(body: { merge_method: "rebase", commit_message: "" }.to_json)
      end
    end

    context "when the user has requested a squash and merge but it's banned" do
      let(:message) { "Squash merges are not allowed on this repository." }

      before do
        pull_request.update!(squash_requested: true)
        message_json = { "message" => message }.to_json
        stub_request(:put, pr_url + "/merge").
          with(body: { merge_method: "squash", commit_message: "" }.to_json).
          to_return(status: 405, body: message_json, headers: json_header)
      end

      it "raises a MergeNotPossible error" do
        expect { action.run }.
          to raise_error(MergePullRequest::MergeNotPossible)
      end
    end
  end

  context "when branch protection is enabled" do
    let(:api_error) { "protected branch" }

    before do
      stub_request(:delete, branch_url).
        to_return(
          status: 422,
          body: { message: api_error }.to_json,
          headers: json_header,
        )
    end

    it "merges the PR and ignores error deleting branch" do
      expect { action.run }.not_to raise_error
      expect(WebMock).
        to have_requested(:put, pr_url + "/merge").
        with(body: { merge_method: "merge", commit_message: "" }.to_json)
    end

    context "with authorized push actors" do
      let(:api_error) do
        "You're not authorized to push to this branch. "\
        "Visit https://help.github.com/articles/about-"\
        "protected-branches/ for more information."
      end

      it "merges the PR and ignores error deleting branch" do
        expect { action.run }.not_to raise_error
        expect(WebMock).
          to have_requested(:put, pr_url + "/merge").
          with(body: { merge_method: "merge", commit_message: "" }.to_json)
      end
    end
  end
end
