# frozen_string_literal: true

require "rails_helper"

RSpec.describe CancelStalePullRequestUpdate, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(update_job: update_job) }

  context "when the update_job isn't updating a PR" do
    let(:update_job) { FactoryBot.create(:update_job) }

    it "no-ops" do
      expect(GitHubHelpers).not_to receive(:installation_access_token_for)
      job.perform_now
    end
  end

  context "when the update_job is updating a PR" do
    let(:pull_request) do
      FactoryBot.create(:account, :dependabot, :active)
      FactoryBot.create(:pull_request, :updating, :bump_test, github_number: 18)
    end
    let(:update_job) do
      pull_request.pull_request_transitions.order(:id).
        find { |t| t.to_state == "updating" }.
        update_job
    end

    before do
      update_job.transition_to!(:enqueued)
      update_job.transition_to!(:processing)
      update_job.transition_to!(
        :processed_with_errors,
        errors: [{ "error-type" => "dependency_file_not_evaluatable" }],
      )
    end

    context "but the PR isn't stale" do
      before { pull_request.transition_to!(:up_to_date) }

      it "no-ops" do
        expect(GitHubHelpers).not_to receive(:installation_access_token_for)
        job.perform_now
      end

      context "because another update run has been triggered" do
        before { pull_request.transition_to!(:updating) }

        it "no-ops" do
          expect(GitHubHelpers).not_to receive(:installation_access_token_for)
          job.perform_now
        end
      end
    end

    context "and the PR is stale" do
      let(:json_header) { { "Content-Type" => "application/json" } }
      let(:repo_url) do
        "#{Dependabot::Application.target_github_internal_api_endpoint}repositories/88632334/"
      end
      let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
      let(:github_comment) { fixture("github_responses/issue_comment.json") }

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
        stub_request(:get, repo_url + "pulls/18").
          to_return(status: 200, body: pr_body, headers: json_header)
        stub_request(:patch, repo_url + "pulls/18").
          with(body: { body: original_description }.to_json).
          to_return(status: 200, body: pr_body, headers: json_header)
        stub_request(:post, repo_url + "issues/18/comments").
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      it "updates the GitHub PR, comments, and marks the PR up-to-date" do
        expect { job.perform_now }.
          to change { pull_request.reload.current_state }.
          from("updating").to("up_to_date")

        expect(WebMock).
          to have_requested(:patch, repo_url + "pulls/18").
          with(body: { body: original_description }.to_json)
        expect(WebMock).
          to have_requested(:post, repo_url + "issues/18/comments").
          with(body: /looking into it/)
      end
    end
  end
end
