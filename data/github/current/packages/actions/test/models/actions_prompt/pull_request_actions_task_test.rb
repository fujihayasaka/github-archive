# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ActionsPrompt::PullRequestActionsTaskTest < GitHub::TestCase
  setup do
    make_trusted_oauth_apps_owner
  end

  context "#repo_candidate?" do
    test "it is a repo candidate if it belongs to a team org and candidate stack" do
      org = create(:organization, plan: "business")
      language = create(:language_name, name: :python)
      repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
      pull_request = setup_pull_request(repo)

      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      assert task.repo_candidate?
    end

    test "it is a repo candidate if it has both HTML and Ruby language" do
      org = create(:organization, plan: "business")
      html_language = create(:language_name, name: :html)
      repo = create(:repository, name: "test-repo", primary_language: html_language, owner: org)
      ruby_language = create(:language, repository: repo, language_name: create(:language_name, name: :ruby))
      pull_request = setup_pull_request(repo)

      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      assert task.repo_candidate?
    end

    test "it is not a repo candidate if it has HTML but not Ruby language" do
      org = create(:organization, plan: "business")
      language = create(:language_name, name: :html)
      repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
      pull_request = setup_pull_request(repo)

      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      refute task.repo_candidate?
    end

    test "it is not a repo candidate if it belongs to a team org but not a candidate language" do
      org = create(:organization, plan: "business")
      language = create(:language_name, name: :ruby)
      repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
      pull_request = setup_pull_request(repo)
      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      refute task.repo_candidate?
    end

    test "it is not a repo candidate if it does not belong to a team org" do
      org = create(:organization, plan: "business_plus")
      ruby_language = create(:ruby_language_name)
      repo = create(:repository, name: "test-repo", primary_language: ruby_language, owner: org)
      pull_request = setup_pull_request(repo)
      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      refute task.repo_candidate?
    end

    test "it is not a repo candidate if it has an action workflow" do
      org = create(:organization, plan: "business")
      language = create(:language_name, name: :python)
      repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
      check_suite = create(:check_suite_for_actions_app, repository: repo, creator: org.admin, name: "Python workflow")
      check_suite.workflow_run
      pull_request = setup_pull_request(repo)
      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      refute task.repo_candidate?
    end
  end

  context "#task_link" do
    test "uses the proper branch reference" do
      org = create(:organization, login: "awesome-org", plan: "business")
      language = create(:language_name, name: :go)
      repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
      pull_request = setup_pull_request(repo)
      task = ActionsPrompt::PullRequestActionsTask.new(pull_request)
      assert_equal(
       "/awesome-org/test-repo/new/master?filename=.github%2Fworkflows%2Fgo.yml&workflow_template=go",
       task.task_link
      )
    end
  end

  def setup_pull_request(repo)
    example_repo :pull_request_source, repo
    pull_request = create(:pull_request, repository: repo, base_repository: repo, head_repository: repo, head_ref: "master-merged-topic")
    pull_request
  end
end unless GitHub.enterprise?
