# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowPipeRunnerTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user = create(:user)
    @project = create(:memex_project, owner: @user)
    @repository = create(:repository, owner: @user)

    @add_issues_workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, skip_action_build: true, trigger_type: :query_matched)
    @add_issues_and_pulls_workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, skip_action_build: true, trigger_type: :query_matched, name: "add_issues_and_pulls")
    @archive_issues_workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, skip_action_build: true, trigger_type: :query_matched, name: "archive_issues")

    # insert add_items before get_issues in database on purpose to test ordering
    add_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: @add_issues_workflow, action_type: :add_project_item, arguments: { "repositoryId" => @repository.id })
    get_issues_action = create(:memex_project_workflow_action, :with_arguments, workflow: @add_issues_workflow, action_type: :get_items, arguments: { "query" => "is:issue is:open", "repositoryId" => @repository.id }, last_updater: @user)
    @add_issues_workflow.actions << [get_issues_action, add_items_action]

    # insert add_items before get_items in database on purpose to test ordering
    add_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: @add_issues_and_pulls_workflow, action_type: :add_project_item, arguments: { "repositoryId" => @repository.id })
    get_all_open_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: @add_issues_and_pulls_workflow, action_type: :get_items, arguments: { "query" => "is:open", "repositoryId" => @repository.id }, last_updater: @user)
    @add_issues_and_pulls_workflow.actions << [get_all_open_items_action, add_items_action]

    get_project_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: @archive_issues_workflow, action_type: :get_project_items, arguments: { "query" => "is:open" })
    archive_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: @archive_issues_workflow, action_type: :archive_project_item, arguments: {})
    @archive_issues_workflow.actions << get_project_items_action
    @archive_issues_workflow.actions << archive_items_action

    # ensure Integration is created
    make_trusted_oauth_apps_owner
    Apps::Internal::MemexAutomation.seed_database!
    Apps::Internal::MemexAutomation.reload!
    @bot = Apps::Internal::MemexAutomation.bot
  end

  def run_workflow(input:, workflow: nil, manual_run: false)
    MemexProjectWorkflow::PipeRunner.run(
      workflow: workflow || @add_issues_workflow,
      input: input,
      actor: @user,
      event_time: Time.now,
      manual_run: manual_run,
      tags: []

    )
  end

  def create_invalid_auto_archive_workflow(project = create(:memex_project))
    set_field_action = build(:memex_project_workflow, memex_project: project).actions.first
    get_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:open", "repositoryId" => @repository.id })
    get_project_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_project_items, arguments: { "query" => "is:closed" })
    archive_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :archive_project_item, arguments: {})
    actions = [set_field_action, get_items_action, get_project_items_action, archive_items_action]

    create(:memex_project_workflow, :skip_validations, name: "Invalid Archive Workflow", enabled: true, memex_project: project, actions: actions, trigger_type: :query_matched)
  end

  def create_auto_archive_workflow_with_duplicate_actions(project = create(:memex_project))
    get_project_items_action_1 = create(:memex_project_workflow_action, :with_arguments, action_type: :get_project_items, arguments: { "query" => "is:closed" })
    get_project_items_action_2 = create(:memex_project_workflow_action, :with_arguments, action_type: :get_project_items, arguments: { "query" => "is:closed" })
    archive_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :archive_project_item, arguments: {})
    actions = [get_project_items_action_1, get_project_items_action_2, archive_items_action]

    create(:memex_project_workflow, :skip_validations, name: "Invalid Archive Workflow with Duplicate Actions", enabled: true, memex_project: project, actions: actions, trigger_type: :query_matched)
  end

  context "workflow configured to add open issues to project" do
    test "adds issues to project" do
      input = [
        create(:issue, repository: @repository),
        create(:issue, repository: @repository)
      ]

      run_workflow(input: input)

      assert_equal 2, @project.memex_project_items.count
    end

    test "does not add issue to project if does not match workflow constraints" do
      input = [
        create(:issue, repository: @repository, state: "closed"),
        create(:issue, repository: @repository, state: "open")
      ]

      run_workflow(input: input)

      assert_equal 1, @project.memex_project_items.count
    end

    test "should return memex project items added to the project" do
      input = [
        create(:issue, repository: @repository),
        create(:issue, repository: @repository)
      ]

      output = run_workflow(input: input)

      assert_equal 2, output.count
      output.each do |output|
        assert output.is_a?(MemexProjectItem)
      end
    end

    test "should skip items that already exist in the project" do
      issue = create(:issue, repository: @repository)
      memex_project_item = create(:memex_project_item, memex_project: @project, content: issue)
      input = [
        issue,
        create(:issue, repository: @repository)
      ]

      output = run_workflow(input: input)

      assert_equal 2, @project.memex_project_items.count
      assert_equal 1, output.count
    end
  end

  context "workflow configured to add open issues and pulls" do
    test "should not add merged PR to project" do
      issue = create(:issue, repository: @repository)
      pull_draft = create(:pull_request, :disable_disk_access, draft: true, repository: @repository, user: @user)
      pull_merged = create(:pull_request, :disable_disk_access, :merged)

      input = [
        issue,
        pull_draft,
        pull_merged
      ]

      output = run_workflow(workflow: @add_issues_and_pulls_workflow, input: input)

      assert_equal 2, @project.memex_project_items.count
      assert_equal 2, output.count
    end
  end

  context "workflow configure to archive project items" do
    test "should archive project items with bot user if not manual_run" do
      memex_project_item = create(:memex_project_item, memex_project: @project)
      refute memex_project_item.archived?

      run_workflow(workflow: @archive_issues_workflow, input: [memex_project_item])

      assert_equal 1, @project.memex_project_items.count
      assert memex_project_item.archived?
      assert_equal @bot, memex_project_item.archiver
    end

    test "should archive project items with bot if manual_run" do
      memex_project_item = create(:memex_project_item, memex_project: @project)
      refute memex_project_item.archived?

      run_workflow(workflow: @archive_issues_workflow, input: [memex_project_item], manual_run: true)

      assert_equal 1, @project.memex_project_items.count
      assert_equal memex_project_item.id, @project.memex_project_items.first.id
      assert @project.memex_project_items.first.archived?
      assert_equal @bot, @project.memex_project_items.first.archiver
    end

    test "should not archive project items if workflow contains invalid actions" do
      project = create(:memex_project)
      invalid_workflow = create_invalid_auto_archive_workflow(project)
      memex_project_item = create(:memex_project_item, memex_project: project)

      run_workflow(workflow: invalid_workflow, input: [memex_project_item], manual_run: false)

      assert_equal 1, project.memex_project_items.count
      refute memex_project_item.archived?
    end

    test "should not archive project items if workflow contains duplicate actions" do
      project = create(:memex_project)
      invalid_workflow = create_auto_archive_workflow_with_duplicate_actions(project)
      memex_project_item = create(:memex_project_item, memex_project: project)

      run_workflow(workflow: invalid_workflow, input: [memex_project_item], manual_run: false)

      assert_equal 1, project.memex_project_items.count
      refute memex_project_item.archived?
    end
  end
end
