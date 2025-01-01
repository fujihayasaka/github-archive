# typed: true
# frozen_string_literal: true

require "test_helper"

class ArchiveProjectItemActionRunner < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @actor = create(:user)
    @project = create(:memex_project)

    @issue = create(:issue)
    @issue_item = create(:memex_project_item, memex_project: @project, content: @issue)

    repo = create(:repository, from_example: :simple)

    @pull_request = create(:pull_request, repository: repo, base_ref: "master", head_ref: "cr-line-endings")
    @pull_request_item = create(:memex_project_item, memex_project: @project, content: @pull_request)

    workflow = create(:memex_project_workflow, memex_project: @project, skip_action_build: true)
    @archive_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: workflow, action_type: :archive_project_item, arguments: {})

    # ensure Integration is created
    make_trusted_oauth_apps_owner
    Apps::Internal::MemexAutomation.seed_database!
    Apps::Internal::MemexAutomation.reload!
  end

  setup do
    @tags = ["foo:bar"]
  end

  def run_workflow(**kwargs)
    MemexProjectWorkflowAction::ArchiveProjectItemActionRunner.run(
      action: kwargs[:action],
      input: kwargs[:input],
      actor: @actor,
      trigger_type: "item_closed",
      tags: @tags
    )
  end

  test "archives project items" do
    refute @issue_item.archived?
    refute @pull_request_item.archived?

    result = run_workflow(action: @archive_items_action, input: [@issue_item, @pull_request_item])

    # verify that the action runner returns an output for the next possible action
    assert_equal 2, result.count
    result.each do |item|
      assert item.archived?
    end

    # verify that archiving was saved to the database
    assert @issue_item.reload.archived?
    assert @pull_request_item.reload.archived?

    assert_dogstats_increment(
      1,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_TRIGGERED,
      tags: [
        "trigger_type:item_closed",
        "runner:piped",
        "action_type:archive_project_item",
      ] + @tags
    )

    assert_dogstats_distribution(
      1,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_DURATION,
      tags: [
        "trigger_type:item_closed",
        "runner:piped",
        "action_type:archive_project_item",
      ] + @tags
    )
  end

  test "raises on an invalid action" do
    add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => 123 })

    assert_raises_with_message(ArgumentError, "action must be of type :archive_project_item") do
      run_workflow(action: add_items_action, input: [@issue_item, @pull_request_item])
    end
  end

  context "item already archived" do
    test "does not raise" do
      refute @pull_request_item.archived?
      @pull_request_item.archive!(@actor)
      assert @pull_request_item.archived?

      run_workflow(action: @archive_items_action, input: [@pull_request_item])

      assert @pull_request_item.reload.archived?

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
        tags: [
          "trigger_type:item_closed",
          "runner:piped",
          "action_type:archive_project_item",
          "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_ARCHIVED}",
        ] + @tags
      )
    end
  end
end
