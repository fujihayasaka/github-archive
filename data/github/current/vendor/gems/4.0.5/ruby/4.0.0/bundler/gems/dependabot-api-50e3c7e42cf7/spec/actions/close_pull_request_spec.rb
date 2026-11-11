# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClosePullRequest do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/88632334" }
  let(:branch_url) { repo_url + "/git/refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_url) { repo_url + "/pulls/18" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:updated_pr_body) do
    fixture("github_responses/pull_request_updated.json")
  end
  let(:open_prs_for_branch_url) do
    "#{repo_url}/pulls?head=hmarr:bump_webmock_to_3.0.1&state=open"
  end

  let(:repo) { FactoryBot.create(:repo, github_id: 88632334) }
  let(:pull_request) do
    FactoryBot.create(:pull_request, status, repo: repo, github_number: 18)
  end

  let(:original_description) do
    "Original description\n\n"\
    "[//]: # (dependabot-automerge-start)\n"\
    "[//]: # (dependabot-automerge-end)\n\n"\
    "---n<details>\n"\
    "<summary>Dependabot commands and options</summary>\n"\
    "</details>"
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:patch, pr_url).
      with(body: { body: original_description }.to_json).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
    stub_request(:patch, pr_url).
      with(body: { state: "closed" }.to_json).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
    stub_request(:get, open_prs_for_branch_url).
      to_return(status: 200, body: "[]", headers: json_header)
    stub_request(:delete, branch_url).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
  end

  context "when the pull request is updating" do
    let(:status) { :updating }

    it "removes the addendum to the PR" do
      action.run

      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { body: original_description }.to_json)
    end

    it "closes the PR on GitHub" do
      action.run

      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { state: "closed" }.to_json)
    end

    it "deletes the branch on GitHub" do
      action.run
      expect(WebMock).to have_requested(:delete, branch_url)
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

    it "marks the PR as closed" do
      expect { action.run }.
        to change { pull_request.reload.current_state }.
        to("closed")
    end

    context "when the pull request is already merged" do
      let(:status) { :merged }

      it "does not attempt to close the PR" do
        expect { action.run }.not_to change(pull_request, :current_state)
      end
    end

    context "when there is a race" do
      before do
        stub_request(:delete, branch_url).
          to_return(
            status: 422,
            body: { message: "Reference does not exist" }.to_json,
            headers: json_header,
          )
      end

      it "marks the PR as closed" do
        expect { action.run }.
          to change { pull_request.reload.current_state }.
          to("closed")
      end
    end

    context "when the repo has been archived" do
      before do
        stub_request(:patch, pr_url).
          with(body: { state: "closed" }.to_json).
          to_return(
            status: 403,
            body: { message: "Repository was archived so is read-" }.to_json,
            headers: json_header,
          )
      end

      it "does not mark the PR as closed" do
        expect { action.run }.
          not_to change { pull_request.reload.current_state }
      end
    end

    context "when GitHub raises an unexpected, temporary 422" do
      before do
        stub_request(:patch, pr_url).
          with(body: { state: "closed" }.to_json).
          to_return(status: 422)
      end

      it "does not mark the PR as closed" do
        expect { action.run }.to raise_error(described_class::GitHubCloseBug)
      end
    end
  end

  context "when the pull request is up-to-date" do
    let(:status) { :up_to_date }

    it "doesn't attempt to remove the PR addendum" do
      action.run

      expect(WebMock).
        not_to have_requested(:patch, pr_url).
        with(body: { body: original_description }.to_json)
    end

    it "closes the PR on GitHub" do
      action.run

      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { state: "closed" }.to_json)
    end

    it "deletes the branch on GitHub" do
      action.run

      expect(WebMock).to have_requested(:delete, branch_url)
    end

    it "marks the PR as closed" do
      expect { action.run }.
        to change { pull_request.reload.current_state }.
        to("closed")
    end

    context "when GitHub 404s" do
      before do
        stub_request(:patch, pr_url).
          with(body: { state: "closed" }.to_json).
          to_return(status: 404)
      end

      context "because the repo has been deleted" do
        before { stub_request(:get, repo_url).to_return(status: 404) }

        it "does not mark the PR as closed" do
          expect { action.run }.
            not_to change { pull_request.reload.current_state }
        end
      end

      context "because the PR has been merged (strange but true)" do
        let(:pr_body) { fixture("github_responses/pull_request_merged.json") }

        it "marks the PR as merged" do
          expect { action.run }.
            to change { pull_request.reload.current_state }.
            to("merged")
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

      it "marks the PR as closed and ignores error deleting branch" do
        expect { action.run }.not_to raise_error
        expect(pull_request.reload.current_state).to eq("closed")
      end

      context "with authorized push actors" do
        let(:api_error) do
          "You're not authorized to push to this branch. "\
          "Visit https://help.github.com/articles/about-"\
          "protected-branches/ for more information."
        end

        it "marks the PR as closed and ignores error deleting branch" do
          expect { action.run }.not_to raise_error
          expect(pull_request.reload.current_state).to eq("closed")
        end
      end

      context "with another unauthorized error message" do
        let(:api_error) do
          "Cannot delete this branch // "\
          "See: https://docs.github.com/articles/about-protected-branches"
        end

        it "marks the PR as closed and ignores error deleting branch" do
          expect { action.run }.not_to raise_error
          expect(pull_request.reload.current_state).to eq("closed")
        end
      end
    end
  end
end
