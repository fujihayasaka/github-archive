# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleIgnoreShowRequest do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      requester: requester,
      comment_body: comment_body,
      comment_id: 301484237,
    )
  end

  let(:requester) { "greysteil" }
  let(:pr_comments_url) do
    repo_url + "issues/#{pull_request.github_number}/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:comment_body) { "@dependabot show * ignore conditions" }
  let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }
  let!(:pull_request) do
    FactoryBot.create(:pull_request, :bump_test, github_number: 122)
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  let(:ignore_conditions) do
    [
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 1.9.0, > 1.3.0",
        dependency_name: "business",
        update_config: pull_request.update_config,
        from_config_file: false,
        updated_at: Time.now.utc - 8400,
        created_at: Time.now.utc - 8400
      ),
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 2, > 1.3.0",
        dependency_name: "business",
        update_config: pull_request.update_config,
        from_config_file: false,
        updated_at: Time.now.utc,
        created_at: Time.now.utc
      ),
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 1.9.0, > 1.8.0",
        dependency_name: "statesman",
        update_config: pull_request.update_config,
        from_config_file: false,
        updated_at: Time.now.utc - 1200,
        created_at: Time.now.utc
      ),
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 1.6.0, > 1.2.0",
        dependency_name: "@business/foo",
        update_config: pull_request.update_config,
        from_config_file: false,
        updated_at: Time.now.utc - 1200,
        created_at: Time.now.utc
      ),
    ]
  end

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
    pull_request.update_config.ignore_conditions << ignore_conditions
  end

  context "when the user has write permissions but the command is invalid" do
    let(:comment_body) { "@dependabot show * unignore conditions" }

    it "creates an invalid command comment" do
      allow(CreateComment).to receive(:new).
        with(
          pull_request: pull_request,
          comment_body: /not valid for this pull request/
        ).and_return(instance_double("CreateComment", run: true))
      action.run
    end
  end

  context "when there are ignore conditions for a specific dependency" do
    let(:comment_body) { "@dependabot show business ignore conditions" }

    it "creates a comment listing the ignore conditions for the specified dependency" do
      allow(CreateComment).to receive(:new).
        with(
          pull_request: pull_request,
          comment_body: /Ignore Conditions/
        ).and_return(instance_double("CreateComment", run: true))
      action.run
    end
  end

  context "when there are ignore conditions for a specific dependency match the pr comment response" do
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:comment_body) { "@dependabot show business ignore conditions" }
    let(:expected_comment_body) do
      "<details>\r\n<summary>Ignore Conditions</summary>\r\n" \
      "<br />\r\n\r\n|Dependency| Ignore Condition|\r\n|-|-|\r\n" \
      "| business | [< 2, > 1.3.0] |\r\n| business | [< 1.9.0, > 1.3.0] |\r\n</details>"
    end
    let(:github_url) { Dependabot::Application.target_github_api_endpoint(repo.account) }
    let(:repo_api_url) { "#{github_url}repos/dependabot/bump-test" }

    before do
      stub_request(:get, repo_api_url).
        to_return(status: 200,
                  body: fixture("pr_creation/create_comment.json"),
                  headers: json_header)
    end

    it "creates a comment listing the ignore conditions for the specified dependency" do
      expect(CreateComment).to receive(:new) do |args|
        expect(args[:pull_request]).to eq(pull_request)
        expect(args[:comment_body]).to eq(expected_comment_body)
      end.and_return(instance_double("CreateComment", run: true))

      action.run
    end
  end

  context "when there are ignore conditions for a specific dependency with complex name" do
    let(:comment_body) { "@dependabot show @business/foo ignore conditions" }

    it "creates a comment listing the ignore conditions for the specified dependency" do
      allow(CreateComment).to receive(:new).
        with(
          pull_request: pull_request,
          comment_body: /Ignore Conditions/
        ).and_return(instance_double("CreateComment", run: true))
      action.run
    end
  end

  context "when there are no ignore conditions for a specific dependency" do
    let(:comment_body) { "@dependabot show foo ignore conditions" }
    let(:ignore_conditions) { [] }

    it "creates a comment stating that no ignore conditions were found for the specified dependency" do
      allow(CreateComment).to receive(:new).
        with(
          pull_request: pull_request,
          comment_body: /No ignore conditions found for the dependency foo/
        ).and_return(instance_double("CreateComment", run: true))
      action.run
    end
  end
end
