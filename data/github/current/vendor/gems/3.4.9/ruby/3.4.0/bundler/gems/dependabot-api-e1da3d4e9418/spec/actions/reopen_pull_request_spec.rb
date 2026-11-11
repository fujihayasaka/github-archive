# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReopenPullRequest do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/88632334/" }
  let(:refs_url) { repo_url + "git/refs" }
  let(:ref_url) { repo_url + "git/refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_url) { repo_url + "pulls/18" }
  let(:branch_ref) { "refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_sha) { "1e2d2afe8320998baecdfe127a49dca9a6650e07" }
  let(:pr_body) { fixture("github_responses/pull_request_closed.json") }
  let(:not_found_body) { fixture("github_responses/not_found.json") }
  let(:updated_pr_body) do
    fixture("github_responses/pull_request_updated.json")
  end

  let(:repo) { FactoryBot.create(:repo, github_id: 88632334) }
  let(:pull_request) do
    FactoryBot.create(:pull_request, status, repo: repo, github_number: 18)
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:get, ref_url).
      to_return(status: 404, body: not_found_body, headers: json_header)
    stub_request(:post, refs_url).
      with(body: { ref: branch_ref, sha: pr_sha }.to_json).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
    stub_request(:patch, pr_url).
      with(body: { state: "open" }.to_json).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
  end

  context "when the pull request is open" do
    let(:status) { :updating }

    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for)
      stub_request(:get, pr_url).
        to_return(status: 200, body: pr_body, headers: json_header)
      stub_request(:post, refs_url).
        with(body: { ref: branch_ref, sha: pr_sha }.to_json).
        to_return(status: 422,
                  body: { message: "Reference already exists" }.to_json,
                  headers: json_header,)
    end

    it "returns the PR" do
      action.run
      expect(WebMock).to have_requested(:post, refs_url).
        with(body: { ref: branch_ref, sha: pr_sha }.to_json)
    end
  end

  context "when the pull request is closed" do
    let(:status) { :closed }

    it "recreates the branch on GitHub" do
      action.run
      expect(WebMock).to have_requested(:post, refs_url).
        with(body: { ref: branch_ref, sha: pr_sha }.to_json)
    end

    it "reopens the PR on GitHub" do
      action.run

      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { state: "open" }.to_json)
    end

    it "marks the PR as up-to-date" do
      expect { action.run }.
        to change { pull_request.current_state(force_reload: true) }.
        to("up_to_date")
    end

    context "when the branch still exists" do
      before do
        stub_request(:post, refs_url).
          to_return(
            status: 422,
            body: { message: "Reference already exists" }.to_json,
            headers: json_header,
          )
      end

      it "reopens the PR on GitHub" do
        action.run

        expect(WebMock).
          to have_requested(:patch, pr_url).
          with(body: { state: "open" }.to_json)
      end

      it "marks the PR as up-to-date" do
        expect { action.run }.
          to change { pull_request.current_state(force_reload: true) }.
          to("up_to_date")
      end
    end

    context "when the branch has no history in common anymore" do
      before do
        stub_request(:get, pr_url).
          to_return(status: 422,
                    body: { message: "has no history in common" }.to_json,
                    headers: json_header,)
        stub_request(:post, pr_comments_url).
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      let(:pr_comments_url) do
        repo_url + "issues/#{pull_request.github_number}/comments"
      end

      let(:github_comment) { fixture("github_responses/issue_comment.json") }

      it "does not mark the PR as up-to-date" do
        expect { action.run }.
          not_to change { pull_request.current_state(force_reload: true) }
      end

      it "comments on the PR" do
        action.run
        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(body: {
            body: "Dependabot tried to reopen this PR, but was told that it "\
                  "no longer has any history in common with the base branch "\
                  "(and therefore couldn't be reopened).",
          }.to_json)
      end
    end

    context "when the branch has no new commits anymore" do
      before do
        stub_request(:get, pr_url).
          to_return(status: 422,
                    body: { message: "There are no new commits on" }.to_json,
                    headers: json_header,)
        stub_request(:post, pr_comments_url).
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      let(:pr_comments_url) do
        repo_url + "issues/#{pull_request.github_number}/comments"
      end

      let(:github_comment) { fixture("github_responses/issue_comment.json") }

      it "does not mark the PR as up-to-date" do
        expect { action.run }.
          not_to change { pull_request.current_state(force_reload: true) }
      end

      it "comments on the PR" do
        action.run
        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(body: {
            body: "Dependabot tried to reopen this PR, but was told that it "\
                  "doesn't include any commits that aren't already on the "\
                  "base branch (and therefore couldn't be reopened).",
          }.to_json)
      end
    end

    context "when the target branch has been deleted" do
      before do
        stub_request(:get, pr_url).
          to_return(status: 422,
                    body: { message: "The a branch has been deleted." }.to_json,
                    headers: json_header,)
        stub_request(:post, pr_comments_url).
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      let(:pr_comments_url) do
        repo_url + "issues/#{pull_request.github_number}/comments"
      end

      let(:github_comment) { fixture("github_responses/issue_comment.json") }

      it "does not mark the PR as up-to-date" do
        expect { action.run }.
          not_to change { pull_request.current_state(force_reload: true) }
      end

      it "comments on the PR" do
        action.run
        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(body: {
            body: "Dependabot tried to reopen this PR, but was told that the "\
                  "target branch has been deleted (and therefore that this PR "\
                  "couldn't be reopened).",
          }.to_json)
      end
    end

    context "when the branch has been force-pushed to" do
      before do
        stub_request(:get, pr_url).
          to_return(
            status: 422,
            body: { message: "branch was force-pushed or recreated." }.to_json,
            headers: json_header,
          )
        stub_request(:post, pr_comments_url).
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      let(:pr_comments_url) do
        repo_url + "issues/#{pull_request.github_number}/comments"
      end

      let(:github_comment) { fixture("github_responses/issue_comment.json") }

      it "does not mark the PR as up-to-date" do
        expect { action.run }.
          not_to change { pull_request.current_state(force_reload: true) }
      end

      it "comments on the PR" do
        action.run
        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(body: {
            body: "Dependabot tried to reopen this PR, but was told that its "\
                  "branch has been force pushed or recreated since it was "\
                  "closed (and therefore can't be restored by GitHub).",
          }.to_json)
      end
    end
  end
end
