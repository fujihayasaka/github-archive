# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergePullRequestJob, type: :job do
  include ActiveJob::TestHelper
  include GitHub::Twirp::DependabotPullRequests::Helpers

  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      dependencies: dependencies,
      created_at: 2.minutes.ago,
    )
  end
  let(:dependencies) do
    [
      {
        "name" => "business",
        "version" => "1.3.4",
        "previous_version" => "1.3.0",
        "requirements" => [],
        "previous_requirements" => [],
        "package_manager" => "bundler",
      },
    ]
  end

  let(:dummy_pr_merger) { instance_double(MergePullRequest, run: nil) }

  before { allow(Dependabot::Logger).to receive(:info) }

  context "when a merge was not explicitly requested" do
    it "no-ops" do
      expect(MergePullRequest).not_to receive(:new)
      expect(Dependabot::Logger).
        to receive(:info).
        with(hash_including(msg: /did not request a merge/))
      job.perform_now
    end
  end

  context "when a merge has been explicitly requested" do
    before { pull_request.update!(merge_requested: true) }

    let(:account) { FactoryBot.create(:account, :active) }
    let(:repo) { FactoryBot.create(:repo, :bump_test, account: account) }
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        head_commit_sha: "headcommitsha",
        dependabot_commit_sha: "headcommitsha",
        github_number: 1,
        repo: repo,
        dependencies: dependencies,
        created_at: 2.minutes.ago,
      )
    end

    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_pr) { fixture("github_responses/pull_request_mergeable.json") }
    let(:repo_url) do
      "#{Dependabot::Application.target_github_internal_api_endpoint}repositories/88632334/"
    end
    let(:comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end
    let(:prs_client) { instance_double(GitHub::Twirp::DependabotPullRequests) }
    let(:ci_status) do
      MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_SUCCESS
    end

    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for)
      stub_request(:get, repo_url + "pulls/1").
        to_return(status: 200, body: github_pr, headers: json_header)
      stub_request(:post, comments_url)

      allow(GitHub::Twirp::DependabotPullRequests).to receive(:new).and_return(prs_client)
      allow(prs_client).to receive(:get_ci_status).
        with(repo: repo, shas: [pull_request.head_commit_sha]).
        and_return({ pull_request.head_commit_sha => resolve_ci_status_symbol(ci_status) })
    end

    context "that is currently updating" do
      before { pull_request.transition_to!(:updating) }

      it "no-ops" do
        expect(MergePullRequest).not_to receive(:new)
        expect(Dependabot::Logger).
          to receive(:info).
          with(hash_including(msg: /not up-to-date/))

        job.perform_now
      end
    end

    context "and the ci status is failure" do
      let(:ci_status) do
        MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_FAILURE
      end

      it "no-ops" do
        expect(Dependabot::Logger).
          to receive(:info).
          with(hash_including(msg: /not success/))
        job.perform_now
      end
    end

    context "and there is no ci status available" do
      before do
        allow(prs_client).to receive(:get_ci_status).
          with(repo: repo, shas: [pull_request.head_commit_sha]).
          and_return({})
      end

      it "delegates to the MergePullRequest action" do
        expect(MergePullRequest).
          to receive(:new).
          with(pull_request: pull_request, require_up_to_date: true).
          and_return(dummy_pr_merger)
        expect(dummy_pr_merger).to receive(:run)

        job.perform_now
      end
    end

    context "and the ci status is pending" do
      let(:ci_status) do
        MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_PENDING
      end

      it "no-ops" do
        expect(MergePullRequest).not_to receive(:new)
        expect(Dependabot::Logger).
          to receive(:info).
          with(hash_including(msg: /not success/))

        job.perform_now
      end
    end

    context "and the ci status is successful" do
      let(:github_pr) do
        fixture("github_responses/pull_request_mergeable.json").
          gsub("1e2d2afe8320998baecdfe127a49dca9a6650e07", "headcommitsha")
      end

      it "delegates to the MergePullRequest action" do
        expect(MergePullRequest).
          to receive(:new).
          with(pull_request: pull_request, require_up_to_date: true).
          and_return(dummy_pr_merger)
        expect(dummy_pr_merger).to receive(:run)

        job.perform_now
      end

      context "when merging the PR fails (on GitHub)" do
        let(:message) do
          "At least 1 approving review is required by reviewers with "\
          "write access."
        end
        let(:pr_comments_url) do
          repo_url + "issues/#{pull_request.github_number}/comments"
        end
        let(:github_comment) do
          fixture("github_responses/issue_comment.json")
        end
        let(:github_comments) do
          fixture("github_responses/issue_comments_not_mentioned.json")
        end

        before do
          expect(MergePullRequest).
            to receive(:new).
            with(pull_request: pull_request, require_up_to_date: true).
            and_return(dummy_pr_merger)
          expect(dummy_pr_merger).
            to receive(:run).
            and_raise(MergePullRequest::MergeNotPossible, message)
        end

        before do
          stub_request(:get, pr_comments_url + "?per_page=100").
            to_return(
              status: 200,
              body: github_comments,
              headers: json_header,
            )
          stub_request(:post, pr_comments_url).
            to_return(status: 200, body: github_comment, headers: json_header)
        end

        it "comments on the PR" do
          job.perform_now
          expect(WebMock).
            to have_requested(:post, pr_comments_url).
            with(body: {
              body: "Dependabot tried to merge this PR, but received "\
                    "the following error from GitHub:\n\n"\
                    "```\nAt least 1 approving review is required by "\
                    "reviewers with write access.\n```",
            }.to_json)
        end

        context "and the failure comment has already been written" do
          let(:github_comments) do
            fixture("github_responses/issue_comments_failed_merge.json")
          end

          it "does not comment on the PR again" do
            job.perform_now
            expect(WebMock).not_to have_requested(:post, pr_comments_url)
          end
        end
      end

      context "and the PR has been edited" do
        let(:commits_body) { fixture("github_responses/commits_edited.json") }

        before do
          stub_request(:get, repo_url + "pulls/1/commits").
            to_return(status: 200, body: commits_body, headers: json_header)
        end

        it "delegates to the MergePullRequest action" do
          expect(MergePullRequest).
            to receive(:new).
            with(pull_request: pull_request, require_up_to_date: true).
            and_return(dummy_pr_merger)
          expect(dummy_pr_merger).to receive(:run)

          job.perform_now
        end
      end

      context "and the PR has not been edited" do
        let(:github_pr) do
          fixture("github_responses/pull_request_mergeable.json").
            gsub("1e2d2afe8320998baecdfe127a49dca9a6650e07", "headcommitsha")
        end

        it "delegates to the MergePullRequest action" do
          expect(MergePullRequest).
            to receive(:new).
            with(pull_request: pull_request, require_up_to_date: true).
            and_return(dummy_pr_merger)
          expect(dummy_pr_merger).to receive(:run)

          job.perform_now
        end
      end
    end

    it "retries transient twirp errors" do
      expect(GitHub::Twirp::DependabotPullRequests).
        to receive(:new).
        and_raise(
          GitHub::Twirp::DependabotPullRequests::TransientTwirpError.new(
            "test",
            Twirp::Error.internal("error"),
          )
        )
      expect { job.perform_now }.to have_enqueued_job(described_class)
    end

    it "retries transient twirp api response errors" do
      expect(GitHub::Twirp::DependabotPullRequests).
        to receive(:new).
        and_raise(
          GitHub::Twirp::DependabotPullRequests::TransientServiceError.new(
            "test",
            MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
              type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
              message: "error"
            )
          )
        )
      expect { job.perform_now }.to have_enqueued_job(described_class)
    end
  end
end
