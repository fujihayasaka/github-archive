# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateCheckOrStatusFailureComment do
  include GitHub::Twirp::DependabotPullRequests::Helpers

  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:repo) { FactoryBot.create(:repo, github_id: 88071876) }
  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      repo: repo,
      head_commit_sha: "headcommitsha",
      dependabot_commit_sha: "headcommitsha",
    )
  end

  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:pr_comments_url) do
    repo_url + "/issues/#{pull_request.github_number}/comments"
  end

  let(:ci_status) do
    MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_SUCCESS
  end

  context "that isn't a merge candidate" do
    let(:pull_request) { FactoryBot.create(:pull_request, repo: repo) }

    it "does not comment on the pull request" do
      action.run
      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "that is a merge candidate" do
    before { pull_request.update!(merge_requested: true) }

    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_comment) { fixture("github_responses/issue_comment.json") }
    let(:github_comments) do
      fixture("github_responses/issue_comments_not_mentioned.json")
    end

    let(:prs_client) { instance_double(GitHub::Twirp::DependabotPullRequests) }

    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for)
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
      stub_request(:get, pr_comments_url + "?per_page=100").
        to_return(status: 200, body: github_comments, headers: json_header)

      allow(GitHub::Twirp::DependabotPullRequests).to receive(:new).and_return(prs_client)
      allow(prs_client).to receive(:get_ci_status).
        with(repo:, shas: [pull_request.head_commit_sha]).
        and_return({ pull_request.head_commit_sha => resolve_ci_status_symbol(ci_status) })
    end

    context "and has passing ci status" do
      it "does not comment on the pull request" do
        action.run
        expect(WebMock).not_to have_requested(:post, pr_comments_url)
      end
    end

    context "and has pending ci status" do
      let(:ci_status) do
        MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_PENDING
      end

      it "does not comment on the pull request" do
        action.run
        expect(WebMock).not_to have_requested(:post, pr_comments_url)
      end
    end

    context "and has a failing ci status" do
      let(:ci_status) do
        MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_FAILURE
      end

      it "comments on the pull request" do
        action.run
        expect(WebMock).to have_requested(:post, pr_comments_url)
      end

      context "when the PR has had a failure comment before" do
        let(:github_comments) do
          fixture("github_responses/issue_comments_failed_ci_before.json")
        end

        it "does not comment on the pull request" do
          action.run
          expect(WebMock).not_to have_requested(:post, pr_comments_url)
        end
      end

      context "when the repo has been deleted" do
        before do
          stub_request(:post, pr_comments_url).
            to_return(status: 404, headers: json_header)
        end

        it "resyncs the repo state" do
          result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
            reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
          )
          dummy_repo_synchronizer = double(run: result)
          expect(SynchronizeRepoState).
            to receive(:new).with(repo: pull_request.repo,
                                  event_source: anything).
            and_return(dummy_repo_synchronizer)
          expect(dummy_repo_synchronizer).to receive(:run)

          expect { action.run }.not_to raise_error
        end
      end
    end
  end
end
