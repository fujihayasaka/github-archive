# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateMissingDependabotPrComment do
  subject(:action) do
    described_class.new(
      repo: repo, github_number: 122, comment_url: "http://example.com",
      pr_created_at: created_at, pr_closed_at: closed_at
    )
  end

  let(:created_at) { 2.days.ago }
  let(:closed_at) { nil }

  let(:repo) { create(:repo, github_id: 88071876) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:pr_comments_url) do
    github_repo_url + "/issues/122/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: repo, event_source: anything).
      and_return(dummy_repo_synchronizer)
  end

  context "when the pull request was deleted from data retention cleanup" do
    let(:closed_at) { 5.years.ago }

    it "comments with the too old message" do
      action.run
      expect(WebMock).
        to have_requested(:post, pr_comments_url).
        with(body: hash_including(
          { "body" => a_string_including("can't perform [the requested action](http://example.com) because this pull request was closed over") }
        ))
    end
  end

  context "when the pull request was recently created" do
    let(:created_at) { 30.minutes.ago }

    it "comments with the recently created message" do
      action.run
      expect(WebMock).
        to have_requested(:post, pr_comments_url).
        with(body: hash_including(
          { "body" => a_string_including("can't perform [the requested action](http://example.com) because this pull request was recently created") }
        ))
    end
  end

  context "when the pull request does not meet any known conditions" do
    it "comments on the pull request" do
      action.run
      expect(WebMock).
        to have_requested(:post, pr_comments_url).
        with(body: hash_including(
          { "body" => a_string_including("can't perform [the requested action](http://example.com) because I don't have any knowledge") }
        ))
    end
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
end
