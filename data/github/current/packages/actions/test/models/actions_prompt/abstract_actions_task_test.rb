# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module ActionsPrompt
  class PoorlyImplementedTask < AbstractActionsTask; end

  class SampleTask < AbstractActionsTask
    attr_reader :repository

    def initialize(repo)
      @repository = repo
    end

    private

    def task_ref
      "main"
    end
  end

  class AbstractActionsTaskTest < GitHub::TestCase
    setup do
      make_trusted_oauth_apps_owner
    end

    context "#repo_candidate?" do
      test "is raises an error if not implemented" do
        assert_raises(NotImplementedError) do
          PoorlyImplementedTask.new.repo_candidate?
        end
      end
    end

    context "#completed?" do
      test "it is completed if the repo has ran an action workflow" do
        org = create(:organization, plan: "business")
        repo = create(:repository, name: "test-repo", owner: org)
        check_suite = create(:check_suite_for_actions_app, repository: repo)
        check_suite.workflow_run
        task = SampleTask.new(repo)
        assert task.completed?
      end

      test "it is not completed if the repo has not ran an action workflow" do
        owner = create(:user)
        org = create(:organization, plan: "business", admin: owner)
        repo = create(:repository, name: "test-repo", owner: org)
        task = SampleTask.new(repo)
        refute task.completed?
      end
    end

    context "#task_link" do
      test "prints go workflow repo url" do
        org = create(:organization, login: "awesome-org", plan: "business")
        language = create(:language_name, name: :go)
        repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
        task = SampleTask.new(repo)
        assert_equal(
         "/awesome-org/test-repo/new/main?filename=.github%2Fworkflows%2Fgo.yml&workflow_template=go",
         task.task_link
        )
      end

      test "prints jekyll workflow repo url" do
        org = create(:organization, login: "awesome-org", plan: "business")
        language = create(:language_name, name: :html)
        repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
        ruby_language = create(:language, repository: repo, language_name: create(:language_name, name: :ruby))
        task = SampleTask.new(repo)
        assert_equal(
         "/awesome-org/test-repo/new/main?filename=.github%2Fworkflows%2Fjekyll.yml&workflow_template=jekyll",
         task.task_link
        )
      end

      test "prints Python workflow repo url" do
        org = create(:organization, login: "awesome-org", plan: "business")
        language = create(:language_name, name: :python)
        repo = create(:repository, name: "test-repo", primary_language: language, owner: org)
        task = SampleTask.new(repo)
        assert_equal(
         "/awesome-org/test-repo/new/main?filename=.github%2Fworkflows%2Fpython-app.yml&workflow_template=python-app",
         task.task_link
        )
      end
    end
  end unless GitHub.enterprise?
end
