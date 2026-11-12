# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClosePullRequestJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(pull_request: pull_request, reason: reason)
  end

  let(:reason) { "dependency_removed" }
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: pull_request.repo,
                            event_source: anything).
      and_return(dummy_repo_synchronizer)
  end

  context "for a PR that is updating" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :updating,
        dependencies: [
          {
            name: "business",
            version: "1.8.0",
          },
        ],
        github_number: 47,
      )
    end

    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) do
      github_url + "repositories/#{pull_request.repo.github_id}"
    end
    let(:pr_url) { repo_url + "/pulls/#{pull_request.github_number}" }
    let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
    let(:comments_url) { repo_url + "/issues/47/comments" }
    let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

    before do
      allow(GitHubHelpers).to receive(:access_token_for)
      stub_request(:get, pr_url).
        to_return(status: 200, body: pr_body, headers: json_header)
      stub_request(:post, comments_url).to_return(status: 200)
      allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
    end

    it "comments on the PR" do
      job.perform_now
      expect(WebMock).to have_requested(:post, comments_url)
    end

    it "closes the PR" do
      expect(dummy_pr_closer).to receive(:run)
      job.perform_now
    end

    context "for a PR that can't be closed due to a bug in GitHub" do
      before do
        allow(dummy_pr_closer).
          to receive(:run).
          and_raise(ClosePullRequest::GitHubCloseBug)
      end

      it "re-enqueues the job, without a comment" do
        expect { job.perform_now }.
          to have_enqueued_job(described_class).
          with(pull_request: pull_request, comment_on_pr: false)
      end
    end

    context "when asked not to comment on the PR" do
      subject(:job) do
        described_class.new(pull_request: pull_request, comment_on_pr: false)
      end

      it "does not comment on the PR" do
        job.perform_now
        expect(WebMock).not_to have_requested(:post, comments_url)
      end

      it "closes the PR" do
        expect(dummy_pr_closer).to receive(:run)
        job.perform_now
      end
    end

    context "when the reason is that the dependency group has been deleted" do
      subject(:job) do
        described_class.new(pull_request: pull_request, reason: "dependency_group_deleted")
      end

      it "comments on the PR" do
        job.perform_now

        expect(WebMock).
          to have_requested(:post, comments_url).
          with(
            body: include("The group that created this PR has been removed from your configuration.")
          )
      end

      it "closes the PR" do
        expect(dummy_pr_closer).to receive(:run)
        job.perform_now
      end
    end

    context "when the reason is that the dependency group is now empty" do
      subject(:job) do
        described_class.new(pull_request: pull_request, reason: "dependency_group_empty")
      end

      it "comments on the PR" do
        job.perform_now

        expect(WebMock).
          to have_requested(:post, comments_url).
          with(
            body: include(
              "None of your dependencies match this group anymore, "\
              "you may need to update your configuration file to remove it or change its rules."
            )
          )
      end

      it "closes the PR" do
        expect(dummy_pr_closer).to receive(:run)
        job.perform_now
      end
    end

    context "when the account is inactive" do
      let(:account) { pull_request.repo.account }

      before do
        account.transition_to!(
          :inactive, installation_id: account.current_installation_id,
        )
      end

      it "doesn't try and close the pull request" do
        expect(dummy_pr_closer).not_to receive(:run)

        job.perform_now
      end
    end

    context "for a PR that can't be fetched" do
      before { stub_request(:get, pr_url).to_return(status: 404) }

      it "resyncs the repo state" do
        expect(dummy_repo_synchronizer).to receive(:run)
        expect(dummy_pr_closer).not_to receive(:run)

        job.perform_now
      end

      context "because our access is blocked" do
        let(:access_blocked) { fixture("github_responses/access_blocked.json") }

        before do
          stub_request(:get, pr_url).
            to_return(status: 403, body: access_blocked, headers: json_header)
        end

        it "resyncs the repo state" do
          expect(dummy_repo_synchronizer).to receive(:run)
          expect(dummy_pr_closer).not_to receive(:run)

          job.perform_now
        end
      end
    end

    context "for a PR that can't be updated as the installation no longer has access to it" do
      before { allow(ClosePullRequest).to receive(:new).and_call_original }

      before do
        pull_request.repo.update!(private: false)
        stub_request(:patch, pr_url).
          to_return(status: 403, body: pr_patch_result, headers: json_header)
      end

      let(:pr_patch_result) { fixture("github_responses/forbidden_unavailable_to_integration.json") }
      let(:github_repo) { fixture("github_responses/repo.json") }

      it "resyncs the repo state" do
        expect(dummy_repo_synchronizer).to receive(:run)
        expect(dummy_pr_closer).not_to receive(:run)
        stub_request(:get, "https://github.com/hmarr").
          to_return(status: 200, body: github_repo, headers: json_header)

        job.perform_now
      end
    end

    context "when the PR is already closed" do
      let(:pr_body) { fixture("github_responses/pull_request_closed.json") }

      it "doesn't comment on the PR" do
        job.perform_now
        expect(WebMock).not_to have_requested(:post, comments_url)
      end
    end

    context "when the PR targets multiple dependencies" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :updating,
          dependencies: [
            {
              name: "business",
              version: "1.8.0",
            },
            {
              name: "statesman",
              version: "2.0.0",
            },
          ],
          github_number: 47,
        )
      end

      it "comments on the PR" do
        job.perform_now
        expect(WebMock).
          to have_requested(:post, comments_url).
            with { |req| expect(req.body).to include("these dependencies are") }
      end

      it "closes the PR" do
        expect(dummy_pr_closer).to receive(:run)
        job.perform_now
      end
    end
  end
end
