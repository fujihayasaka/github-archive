# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleRebaseRequest do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      requester: requester,
      comment_id: comment_id,
      comment_type: comment_type,
    )
  end

  let(:requester) { "greysteil" }
  let(:comment_id) { "123" }
  let(:comment_type) { "issue_comment" }
  let!(:pull_request) do
    FactoryBot.create(:pull_request, :bump_test, github_number: 122)
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:reactions_url) { repo_url + "issues/comments/#{comment_id}/reactions" }
  let(:github_reaction) { fixture("github_responses/reaction.json") }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:post, reactions_url).
      to_return(status: 201, body: github_reaction, headers: json_header)
  end

  it "triggers a rebase" do
    expect { action.run }.
      to have_enqueued_job(HandleRebaseRequestJob).
      with(pull_request: pull_request)
  end

  it "acknowledges the request on GitHub" do
    action.run
    expect(WebMock).
      to have_requested(:post, reactions_url).
      with(body: { content: "+1" }.to_json)
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
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "doesn't trigger a recreate and comments on the PR" do
      expect { action.run }.
        not_to have_enqueued_job(HandleRecreateRequestJob)
      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "Sorry, only users with push access can use that command.",
          }.to_json,
        )
    end
  end

  context "when the pull request is a grouped update, but the group has been deleted" do
    let(:dependency_group) do
      FactoryBot.create(:dependency_group, :deleted)
    end

    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        :bump_test,
        github_number: 122,
        dependency_group: dependency_group,
        grouped_update: true
      )
    end

    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end
    let(:github_comment) do
      fixture("github_responses/issue_comment.json")
    end

    before do
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "doesn't trigger a recreate and comments on the PR" do
      expect { action.run }.
        not_to have_enqueued_job(HandleRecreateRequestJob)

      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "Sorry, the '#{dependency_group.name}' group has been removed from your config " \
                  "so we do not know how to rebase this PR.",
          }.to_json,
        )
    end
  end

  context "when the pull request is a grouped update, but the group is gone" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        :bump_test,
        github_number: 122,
        dependency_group: nil,
        grouped_update: true
      )
    end

    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end
    let(:github_comment) do
      fixture("github_responses/issue_comment.json")
    end

    before do
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "doesn't trigger a recreate and comments on the PR" do
      expect { action.run }.
        not_to have_enqueued_job(HandleRebaseRequestJob)

      expect(WebMock).to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "Sorry, the 'unknown' group has been removed from your config " \
                  "so we do not know how to rebase this PR.",
          }.to_json,
        )
    end
  end

  context "when the pull request is a multi-ecosystem update" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, multi_ecosystem_config:) }
    let(:pr_comments_url) { repo_url + "issues/#{pull_request.github_number}/comments" }

    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        :bump_test,
        repo: update_config.repo,
        update_config:,
        github_number: 123,
        dependency_group: nil,
        grouped_update: true
      )
    end

    it "triggers a rebase" do
      expect { action.run }.
        to have_enqueued_job(HandleRebaseRequestJob).
        with(pull_request: pull_request)

      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "when the pull request is a grouped security update" do
    let(:update_job) do
      FactoryBot.create(
        :update_job,
        security_updates_only: true
      )
    end
    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        :bump_test,
        update_job: update_job,
        github_number: 122,
        dependency_group: nil,
        grouped_update: true
      )
    end

    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end
    let(:github_comment) do
      fixture("github_responses/issue_comment.json")
    end

    before do
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    it "triggers a rebase" do
      expect { action.run }.to have_enqueued_job(HandleRebaseRequestJob)

      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end
end
