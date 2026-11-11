# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleMergeRequest do
  include GitHub::Twirp::DependabotPullRequests::Helpers

  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      requester: requester,
      comment_id: comment_id,
      comment_type: comment_type,
    )
  end

  let(:requester) { "greysteil" }
  let(:pr_comments_url) do
    repo_url + "issues/#{pull_request.github_number}/comments"
  end
  let(:github_comments) do
    fixture("github_responses/issue_comments_not_mentioned.json")
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:reactions_url) { repo_url + "issues/comments/#{comment_id}/reactions" }
  let(:github_reaction) { fixture("github_responses/reaction.json") }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:comment_id) { "123" }
  let(:comment_type) { "issue_comment" }
  let!(:pull_request) do
    FactoryBot.create(
      :pull_request, :bump_test,
      github_number: 122,
      head_commit_sha: "headcommitsha",
      dependabot_commit_sha: "headcommitsha",
    )
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:branch_url) { repo_url + "git/refs/heads/bump_webmock_to_3.0.1" }
  let(:open_prs_for_branch_url) do
    "#{repo_url}pulls?head=dependabot:bump_webmock_to_3.0.1&state=open"
  end
  let(:merged_pr_body) { fixture("github_responses/merge_pull_request.json") }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }
  let(:prs_client) { instance_double(GitHub::Twirp::DependabotPullRequests) }
  let(:ci_status) do
    MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_SUCCESS
  end

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:patch, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:post, reactions_url).
      to_return(status: 201, body: github_reaction, headers: json_header)
    stub_request(:put, pr_url + "/merge").
      with(body: { merge_method: "merge", commit_message: "" }.to_json).
      to_return(status: 200, body: merged_pr_body, headers: json_header)
    stub_request(:get, open_prs_for_branch_url).
      to_return(status: 200, body: "[]", headers: json_header)
    stub_request(:delete, branch_url).
      to_return(status: 204, headers: json_header)

    allow(GitHub::Twirp::DependabotPullRequests).to receive(:new).and_return(prs_client)
    allow(prs_client).to receive(:get_ci_status).
      with(repo: repo, shas: [pull_request.head_commit_sha]).
      and_return({ pull_request.head_commit_sha => resolve_ci_status_symbol(ci_status) })
  end

  context "with new auto-merge logic" do
    let(:enable_auto_merge) { instance_double(EnableAutoMerge, run: nil) }
    let(:merge_pull_request) { instance_double(MergePullRequest, run: nil) }

    before do
      allow(EnableAutoMerge).to receive(:new).and_return(enable_auto_merge)
      allow(MergePullRequest).to receive(:new).and_return(merge_pull_request)

      repo.enable_feature(:new_merge_command)
    end

    context "when the branch is clean" do
      it "merges the pull request" do
        allow(enable_auto_merge).to receive(:run).
          and_return(EnableAutoMerge::EnableAutoMergeResult.new(outcome: :clean))
        expect(merge_pull_request).to receive(:run)

        action.run
      end
    end

    context "when there is an error enabling auto-merge" do
      before do
        stub_request(:post, pr_comments_url).
          to_return(status: 200, body: github_comment, headers: json_header)
      end

      it "comments a helpful message" do
        allow(enable_auto_merge).to receive(:run).
          and_return(EnableAutoMerge::EnableAutoMergeResult.new(
                       outcome: :error,
                       message: "Pull request is already merged"
                     ))

        action.run

        body = "There was an error enabling auto-merge:\n\n```\nPull request is already merged\n```"
        expect(WebMock).to have_requested(:post, pr_comments_url).
          with(body: { body: body }.to_json)
      end
    end
  end

  context "with insufficient permissions" do
    let(:permission_level) { "read" }
    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end
    let(:github_comment) do
      fixture("github_responses/issue_comment.json")
    end

    before do
      stub_request(:get, pr_comments_url + "?per_page=100").
        to_return(status: 200, body: github_comments, headers: json_header)
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "doesn't update the pull request and comments on the PR" do
      expect { action.run }.
        not_to change { PullRequest.find(pull_request.id).merge_requested }
      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "Sorry, only users with push access can use that command.",
          }.to_json,
        )
    end

    context "when triggered_by_review_approval is true" do
      subject(:action) do
        described_class.new(
          pull_request: pull_request,
          requester: requester,
          comment_id: comment_id,
          comment_type: comment_type,
          triggered_by_review_approval: true
        )
      end

      it "doesn't update the pull request and doesn't comment on the PR" do
        expect { action.run }.
          not_to change { PullRequest.find(pull_request.id).merge_requested }
        expect(WebMock).not_to have_requested(:post, pr_comments_url)
      end
    end
  end

  context "with failing ci status" do
    let(:ci_status) do
      MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_FAILURE
    end

    it "marks the PR as having had a merge requested" do
      expect { action.run }.
        to change { PullRequest.find(pull_request.id).merge_requested }.
        from(false).to(true)
    end

    context "with squash_commits requested" do
      subject(:action) do
        described_class.new(
          pull_request: pull_request,
          requester: requester,
          comment_id: comment_id,
          comment_type: comment_type,
          squash_commits: true,
        )
      end

      it "marks the PR as having had a squash and merge requested" do
        expect { action.run }.
          to change { PullRequest.find(pull_request.id).merge_requested }.
          from(false).to(true).
          and change { PullRequest.find(pull_request.id).squash_requested }.
          from(false).to(true)
      end
    end

    it "acknowledges the request on GitHub" do
      action.run
      expect(WebMock).
        to have_requested(:post, reactions_url).
        with(body: { content: "+1" }.to_json)
    end

    it "enqueues a job to do the merge" do
      expect { action.run }.
        to have_enqueued_job(MergePullRequestJob).
        with(pull_request: pull_request)
    end

    it "lets the user know what's going on" do
      action.run
      expect(WebMock).to have_requested(:patch, pr_url).
        with { |r| expect(r.body).to include("as requested by @greysteil") }
    end
  end

  context "with no ci status" do
    before do
      repo.update!(has_ci: false)
      allow(prs_client).to receive(:get_ci_status).
        with(repo: repo, shas: [pull_request.head_commit_sha]).
        and_return({})
    end

    it "merges the pull requests" do
      action.run

      expect(WebMock).
        to have_requested(:put, pr_url + "/merge").
        with(body: { merge_method: "merge", commit_message: "" }.to_json)
    end

    context "when the repo has tests" do
      before { repo.update!(has_ci: true) }

      it "marks the PR as having had a merge requested" do
        expect { action.run }.
          to change { PullRequest.find(pull_request.id).merge_requested }.
          from(false).to(true)
      end

      it "enqueues a job to do the merge" do
        expect { action.run }.
          to have_enqueued_job(MergePullRequestJob).
          with(pull_request: pull_request)
      end

      it "lets the user know what's going on" do
        action.run
        expect(WebMock).to have_requested(:patch, pr_url).
          with { |r| expect(r.body).to include("as requested by @greysteil") }
      end
    end
  end

  context "with successful ci status" do
    it "merges the pull requests" do
      action.run

      expect(WebMock).
        to have_requested(:put, pr_url + "/merge").
        with(body: { merge_method: "merge", commit_message: "" }.to_json)
    end

    context "when the PR is updating" do
      before { pull_request.transition_to!(:updating) }

      before do
        stub_request(:patch, pr_url).
          to_return(status: 200, body: pr_body, headers: json_header)
      end

      it "marks the PR as having had a merge requested" do
        expect { action.run }.
          to change { PullRequest.find(pull_request.id).merge_requested }.
          from(false).to(true)
      end

      it "enqueues a job to update the PR" do
        expect { action.run }.
          to have_enqueued_job(CheckPullRequestForConflictsJob).with(
            pull_request: pull_request,
            event_source: "action.handle_merge_request",
            manual: true
          )
      end

      it "lets the user know what's going on" do
        action.run
        expect(WebMock).to have_requested(:patch, pr_url).
          with { |r| expect(r.body).to include("as requested by @greysteil") }
      end
    end

    context "when the PR can't be merged" do
      let(:pr_body) { fixture("github_responses/pull_request_dirty.json") }

      before do
        stub_request(:patch, pr_url).
          to_return(status: 200, body: pr_body, headers: json_header)
      end

      it "marks the PR as having had a merge requested" do
        expect { action.run }.
          to change { PullRequest.find(pull_request.id).merge_requested }.
          from(false).to(true)
      end

      it "enqueues a job to update the PR" do
        expect { action.run }.
          to have_enqueued_job(CheckPullRequestForConflictsJob).with(
            pull_request: pull_request,
            event_source: "action.handle_merge_request",
            manual: true
          )
      end

      it "lets the user know what's going on" do
        action.run
        expect(WebMock).to have_requested(:patch, pr_url).
          with { |r| expect(r.body).to include("as requested by @greysteil") }
      end

      context "because the branch is protected" do
        let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
        let(:message) do
          "At least 2 approving reviews are required by reviewers with write "\
          "access."
        end

        before do
          message_json = { "message" => message }.to_json
          stub_request(:put, pr_url + "/merge").
            with(body: { merge_method: "merge", commit_message: "" }.to_json).
            to_return(status: 405, body: message_json, headers: json_header)
          stub_request(:get, pr_comments_url + "?per_page=100").
            to_return(status: 200, body: github_comments, headers: json_header)
          stub_request(:post, pr_comments_url).
            to_return(status: 200, body: github_comment, headers: json_header)
        end

        it "lets the user know what's going on" do
          action.run
          expect(WebMock).to have_requested(:post, pr_comments_url).
            with(
              body: {
                body: "Dependabot tried to merge this PR, but received the "\
                      "following error from GitHub:\n\n```\n"\
                      "At least 2 approving reviews are required by reviewers "\
                      "with write access.\n```",
              }.to_json,
            )
        end

        context "and the failure comment has already been written" do
          let(:github_comments) do
            fixture("github_responses/issue_comments_failed_merge.json")
          end

          it "does not comment on the PR again" do
            action.run
            expect(WebMock).not_to have_requested(:post, pr_comments_url)
          end
        end

        context "and the merge request was made due to an approving review" do
          subject(:action) do
            described_class.new(
              pull_request: pull_request,
              requester: requester,
              comment_id: comment_id,
              comment_type: comment_type,
              triggered_by_review_approval: true
            )
          end

          it "does not comment on the PR again" do
            action.run
            expect(WebMock).not_to have_requested(:post, pr_comments_url)
          end

          context "and the failure was unrelated to reviews" do
            let(:message) { "You're not authorized to push to this branch." }

            it "lets the user know what's going on" do
              action.run
              expect(WebMock).to have_requested(:post, pr_comments_url).
                with(
                  body: {
                    body: "Dependabot tried to merge this PR, but received "\
                          "the following error from GitHub:\n\n```\n"\
                          "You're not authorized to push to this branch.\n```",
                  }.to_json,
                )
            end
          end
        end
      end
    end
  end

  context "with pending ci status" do
    let(:ci_status) do
      MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_PENDING
    end

    it "marks the PR as having had a merge requested" do
      expect { action.run }.
        to change { PullRequest.find(pull_request.id).merge_requested }.
        from(false).to(true)
    end

    it "enqueues a job to do the merge" do
      expect { action.run }.
        to have_enqueued_job(MergePullRequestJob).
        with(pull_request: pull_request)
    end

    it "lets the user know what's going on" do
      action.run
      expect(WebMock).to have_requested(:patch, pr_url).
        with { |r| expect(r.body).to include("as requested by @greysteil") }
    end

    it "doesn't comment on the pull request" do
      action.run
      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "when already merged" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test, :merged,
        github_number: 122,
        head_commit_sha: "headcommitsha",
        dependabot_commit_sha: "headcommitsha",
      )
    end
    let(:checks_data) { "unused" }
    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end

    before do
      stub_request(:get, pr_comments_url + "?per_page=100").
        to_return(status: 200, body: github_comments, headers: json_header)
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "lets the user know what's going on" do
      action.run
      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "This PR has already been merged! 🎉",
          }.to_json,
        )
    end
  end

  context "when already closed" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test, :closed,
        github_number: 122,
        head_commit_sha: "headcommitsha",
        dependabot_commit_sha: "headcommitsha",
      )
    end
    let(:checks_data) { "unused" }
    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end

    before do
      stub_request(:get, pr_comments_url + "?per_page=100").
        to_return(status: 200, body: github_comments, headers: json_header)
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "lets the user know what's going on" do
      action.run
      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "This PR is closed - you'll need to reopen it before "\
                  "merging.",
          }.to_json,
        )
    end
  end
end
