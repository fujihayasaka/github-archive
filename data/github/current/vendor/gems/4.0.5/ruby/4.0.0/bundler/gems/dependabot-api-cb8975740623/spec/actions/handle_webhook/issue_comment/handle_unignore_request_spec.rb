# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleUnignoreRequest do
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
  let(:comment_body) { "@dependabot unignore business" }
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
      ),
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 2, > 1.3.0",
        dependency_name: "business",
        update_config: pull_request.update_config,
        from_config_file: false,
      ),
      FactoryBot.build(
        :ignore_condition,
        version_requirement: "< 1.9.0, > 1.8.0",
        dependency_name: "statesman",
        update_config: pull_request.update_config,
        from_config_file: false,
      ),
    ]
  end

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
    allow(GitHubHelpers).to receive(:access_token_for)
    allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
  end

  shared_examples "validate for a grouped update pull request" do |comment_body|
    let(:comment_body) { comment_body }

    before do
      pull_request.grouped_update = true
      pull_request.update_config.ignore_conditions << ignore_conditions
    end

    it "calls the unignore condition for a dependency" do
      expect(action.run).to be_truthy
    end

    it "initiates a recreate request job and creates a success unignore comment" do
      expect(HandleRecreateRequestJob).to receive(:perform_later).once.with(pull_request: pull_request)
      expect(CreateComment).to receive(:new).once.with(pull_request: pull_request,
                                                       comment_body: anything).and_call_original
      action.run
    end
  end

  context "with a valid unignore command with dependency name and ignore condition in a grouped update pull request" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    include_examples "validate for a grouped update pull request",
                     "@dependabot unignore business [< 1.9.0, > 1.3.0]",
                     ["business", "< 1.9.0, > 1.3.0"]
  end

  context "with a valid unignore command with only dependency name in a grouped update pull request" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    include_examples "validate for a grouped update pull request", "@dependabot unignore business",
                     ["business", nil]
  end

  context "with invalid unignore command for a grouped update pull request" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    let(:comment_body) { "@dependabot unignore this dependency" }

    it "calls CreateComment with a valid command hints" do
      msg = "Sorry, the command you entered is not valid. Valid commands:\n"\
      "`@dependabot unignore <dependency name> <ignore condition>`\n" \
      "`@dependabot unignore <dependency name> dependency`"

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      action.run
    end
  end

  context "when ignore condition is not found or removed in a grouped update pull request" do
    let(:comment_body) { "@dependabot unignore business [< 2.0, >1.8.0]" }

    before do
      pull_request.grouped_update = true
      pull_request.update_config.ignore_conditions << ignore_conditions
      allow(FindOrRemoveIgnoreCondition).to receive(:new).and_return(instance_double(FindOrRemoveIgnoreCondition,
                                                                                     run: false))
    end

    it "does not initiate a recreate request job or create a success unignore comment" do
      expect(HandleRecreateRequestJob).not_to receive(:perform_later)
      msg = "No dependency name (business) or ignore conditions found to unignore."

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      expect(action.run).to be_falsey
    end
  end

  context "when dependency not found in a grouped update pull request" do
    let(:comment_body) { "@dependabot unignore foo [< 2.0, >1.8.0]" }

    before do
      pull_request.grouped_update = true
      pull_request.update_config.ignore_conditions << ignore_conditions
      allow(FindOrRemoveIgnoreCondition).to receive(:new).and_return(instance_double(FindOrRemoveIgnoreCondition,
                                                                                     run: false))
    end

    it "does not initiate a recreate request job or create a success unignore comment" do
      expect(HandleRecreateRequestJob).not_to receive(:perform_later)
      msg = "No dependency name (foo) or ignore conditions found to unignore."

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      expect(action.run).to be_falsey
    end
  end

  shared_examples "validate for a non grouped update pull request" do |comment_body|
    let(:comment_body) { comment_body }

    before do
      pull_request.grouped_update = false
      pull_request.update_config.ignore_conditions << ignore_conditions
    end

    it "calls the unignore condition for a dependency" do
      expect(action.run).to be_truthy
    end

    it "initiates a recreate request job and creates a success unignore comment" do
      expect(HandleRecreateRequestJob).to receive(:perform_later).once.with(pull_request: pull_request)
      expect(CreateComment).to receive(:new).once.with(pull_request: pull_request,
                                                       comment_body: anything).and_call_original
      action.run
    end
  end

  context "with a valid unignore command with dependency name and ignore condition in a non GU pull request" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }],
      )
    end

    include_examples "validate for a non grouped update pull request",
                     "@dependabot unignore business [< 1.9.0, > 1.3.0]",
                     ["business", "< 1.9.0, > 1.3.0"]
  end

  context "with a valid unignore command with only dependency name in a non GU pull request" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }],
      )
    end

    include_examples "validate for a non grouped update pull request", "@dependabot unignore business",
                     ["business", nil]
  end

  context "with invalid unignore command for a non GU pull request" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }],
      )
    end

    let(:comment_body) { "@dependabot unignore * dependency" }

    it "calls CreateComment with a valid command hints" do
      msg = "Sorry, the command you entered is not valid. Valid commands:\n"\
      "`@dependabot unignore <dependency name> <ignore condition>`\n" \
      "`@dependabot unignore <dependency name> dependency`"

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      action.run
    end
  end

  context "when ignore condition is not found or removed in a non GU pull request" do
    let(:comment_body) { "@dependabot unignore business [< 2.0, >1.8.0]" }
    let(:ignore_conditions) do
      [
        FactoryBot.build(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.build(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.grouped_update = false
      pull_request.update_config.ignore_conditions << ignore_conditions
      allow(FindOrRemoveIgnoreCondition).to receive(:new).and_return(instance_double(FindOrRemoveIgnoreCondition,
                                                                                     run: false))
    end

    it "does not initiate a recreate request job or create a success unignore comment" do
      expect(HandleRecreateRequestJob).not_to receive(:perform_later)
      msg = "No dependency name (business) or ignore conditions found to unignore."

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      expect(action.run).to be_falsey
    end
  end

  context "when dependency name is not found in a non GU pull request" do
    let(:comment_body) { "@dependabot unignore business [< 1.9.0, > 1.3.0]" }
    let(:ignore_conditions) do
      [
        FactoryBot.build(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "statesman",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.build(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "statesman",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.grouped_update = false
      pull_request.update_config.ignore_conditions << ignore_conditions
      allow(FindOrRemoveIgnoreCondition).to receive(:new).and_return(instance_double(FindOrRemoveIgnoreCondition,
                                                                                     run: false))
    end

    it "does not initiate a recreate request job or create a success unignore comment" do
      expect(HandleRecreateRequestJob).not_to receive(:perform_later)
      msg = "No dependency name (business) or ignore conditions found to unignore."

      expect(CreateComment).to receive(:new).with(
        pull_request: pull_request,
        comment_body: msg
      ).and_call_original

      expect(action.run).to be_falsey
    end
  end
end
