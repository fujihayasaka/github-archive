# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestBaseBranch do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }
  let(:github_number) { pull_request.github_number }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{pull_request.repo.github_id}/" }
  let(:pr_body) { fixture("github_responses/pull_request_updated.json") }
  let(:compare_body) { fixture("github_responses/commit_compare.json") }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, repo_url + "pulls/#{github_number}").
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:patch, repo_url + "pulls/#{github_number}").
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:get, repo_url + "compare/master...develop").
      to_return(status: 200, body: compare_body, headers: json_header)
  end

  context "when the default branch has changed" do
    before do
      pr_body.gsub!('"default_branch": "master"', '"default_branch": "develop"')
    end

    it "updates the pull request base branch" do
      action.run

      expect(WebMock).
        to have_requested(:patch, repo_url + "pulls/#{github_number}").
        with(body: { base: "develop" }.to_json)
    end

    context "when the new branch is behind the old one" do
      before { compare_body.gsub!('"status": "ahead"', '"status": "behind"') }

      let(:pull_request) { FactoryBot.create(:pull_request) }

      it "enqueues an PR update job that will update the base branch" do
        expect { action.run }.
          to have_enqueued_job(RebasePullRequestIfNewCommitsJob).
          with(pull_request: pull_request)
      end
    end

    context "when the old branch no longer exists" do
      before do
        compare_body = fixture("github_responses/not_found.json")
        stub_request(:get, repo_url + "compare/master...develop").
          to_return(status: 404, body: compare_body, headers: json_header)
      end

      let(:pull_request) { FactoryBot.create(:pull_request) }

      it "enqueues an PR update job that will update the base branch" do
        expect { action.run }.
          to have_enqueued_job(RebasePullRequestIfNewCommitsJob).
          with(pull_request: pull_request)
      end
    end

    context "when the new branch includes the PRs commits" do
      before do
        stub_request(:patch, repo_url + "pulls/#{github_number}").
          to_return(status: 422,
                    body: { message: "There are no new commits on" }.to_json,
                    headers: json_header,)
      end

      it "enqueues an PR update job that will close the pull request" do
        expect { action.run }.
          to have_enqueued_job(RebasePullRequestIfNewCommitsJob).
          with(pull_request: pull_request)
      end
    end

    context "when there is a race and we lose" do
      before do
        github_response = fixture("github_responses/pr_exists.json")
        stub_request(:patch, repo_url + "pulls/#{github_number}").
          to_return(status: 422, body: github_response, headers: json_header)
      end

      it "quietly ignores the race" do
        action.run

        expect(WebMock).
          to have_requested(:patch, repo_url + "pulls/#{github_number}").
          with(body: { base: "develop" }.to_json)
      end
    end

    context "for a PR that specified the old branch explicitly" do
      before { pull_request.update_config.target_branch = "master" }

      it "does not update the pull request base branch" do
        expect { action.run }.
          not_to have_enqueued_job(RebasePullRequestIfNewCommitsJob)
        expect(WebMock).
          not_to have_requested(:patch, repo_url + "pulls/#{github_number}")
      end
    end
  end

  context "when the default branch has not changed" do
    it "does not update the pull request base branch" do
      expect { action.run }.
        not_to have_enqueued_job(RebasePullRequestIfNewCommitsJob)

      expect(WebMock).
        not_to have_requested(:patch, repo_url + "pulls/#{github_number}")
    end

    context "but the target branch for this update config has" do
      before { pull_request.update_config.target_branch = "custom" }

      before do
        stub_request(:get, repo_url + "compare/master...custom").
          to_return(status: 200, body: compare_body, headers: json_header)
      end

      it "updates the pull request base branch" do
        action.run

        expect(WebMock).
          to have_requested(:patch, repo_url + "pulls/#{github_number}").
          with(body: { base: "custom" }.to_json)
      end
    end
  end
end
