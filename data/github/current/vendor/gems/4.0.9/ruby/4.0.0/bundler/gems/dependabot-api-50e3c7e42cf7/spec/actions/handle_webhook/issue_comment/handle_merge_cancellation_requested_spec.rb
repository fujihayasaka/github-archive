# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleMergeCancellationRequest do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      requester: requester,
      comment_id: comment_id,
      comment_type: comment_type,
    )
  end

  let(:requester) { "greysteil" }
  let(:reactions_url) { repo_url + "issues/comments/#{comment_id}/reactions" }
  let(:github_reaction) { fixture("github_responses/reaction.json") }
  let(:comment_id) { "123" }
  let(:comment_type) { "issue_comment" }
  let!(:pull_request) do
    FactoryBot.create(
      :pull_request, :bump_test,
      github_number: 122,
      merge_requested: merge_requested,
    )
  end

  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:post, reactions_url).
      to_return(status: 201, body: github_reaction, headers: json_header)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:patch, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
  end

  context "with a PR that has had a merge requested" do
    let(:merge_requested) { true }

    it "marks the PR as not requiring a merge" do
      expect { action.run }.
        to change { pull_request.reload.merge_requested }.
        from(true).to(false)
    end

    it "acknowledges the request on GitHub" do
      action.run
      expect(WebMock).
        to have_requested(:post, reactions_url).
        with(body: { content: "+1" }.to_json)
    end

    it "updates the pull request description" do
      action.run
      expect(WebMock).to have_requested(:patch, pr_url).
        with { |r|
          expect(JSON.parse(r.body)["body"]).
            to include("automerge-start)\n[//]: # (dependabot-automerge-end)")
        }
    end
  end

  context "with a PR that has not had a merge requested" do
    let(:merge_requested) { false }

    it "doesn't update the merge_requested flag" do
      expect(pull_request.reload.merge_requested).to eq(false)
      action.run
      expect(pull_request.reload.merge_requested).to eq(false)
    end

    it "doesn't acknowledge the request on GitHub" do
      action.run
      expect(WebMock).not_to have_requested(:post, reactions_url)
    end

    context "but the account has merge_on_approval enabled" do
      before { pull_request.account.update!(merge_on_approval: true) }

      let(:pr_body) do
        fixture("github_responses/pull_request_not_automerging.json")
      end

      it "marks the PR as having automerges blocked" do
        expect { action.run }.
          to change { pull_request.reload.automerge_block_requested }.
          from(false).to(true)
      end

      it "acknowledges the request on GitHub" do
        action.run
        expect(WebMock).
          to have_requested(:post, reactions_url).
          with(body: { content: "+1" }.to_json)
      end

      it "updates the pull request description" do
        action.run
        expect(WebMock).to have_requested(:patch, pr_url).
          with { |r|
            expect(JSON.parse(r.body)["body"]).
              to include("automerge-start)\nDependabot will **not** automati")
          }
      end
    end
  end
end
