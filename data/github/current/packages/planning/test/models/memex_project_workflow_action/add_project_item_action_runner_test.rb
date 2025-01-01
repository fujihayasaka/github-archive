# typed: true
# frozen_string_literal: true

require "test_helper"

class AddProjectItemActionRunner < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @actor = create(:user)
    @project = create(:memex_project)

    @issue = create(:issue)

    repo = create(:repository, from_example: :simple)

    @pull_request = create(:pull_request, repository: repo, base_ref: "master", head_ref: "cr-line-endings")

    workflow = create(:memex_project_workflow, memex_project: @project, skip_action_build: true)
    @add_items_action = create(:memex_project_workflow_action, :with_arguments, workflow: workflow, action_type: :add_project_item, arguments: {
      "repositoryId" => repo.id
    })

    # ensure Integration is created
    make_trusted_oauth_apps_owner
    Apps::Privileged::MemexAutomation.seed_database!
    Apps::Privileged::MemexAutomation.reload!
  end

  setup do
    @tags = ["foo:bar"]
  end

  def run_workflow(**kwargs)
    MemexProjectWorkflowAction::AddProjectItemActionRunner.run(
      action: kwargs[:action],
      input: kwargs[:input],
      actor: @actor,
      trigger_type: "query_matched",
      tags: @tags
    )
  end

  test "adds project items" do
    result = run_workflow(action: @add_items_action, input: [@issue, @pull_request])

    # verify that the action runner returns an output for the next possible action
    assert_equal 2, result.count
    result.each do |item|
      assert @project.memex_project_items.include?(item)
    end

    assert_dogstats_increment(
      1,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_TRIGGERED,
      tags: [
        "trigger_type:query_matched",
        "runner:piped",
        "action_type:add_project_item",
      ] + @tags
    )

    assert_dogstats_distribution(
      1,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_DURATION,
      tags: [
        "trigger_type:query_matched",
        "runner:piped",
        "action_type:add_project_item",
      ] + @tags
    )
  end

  test "raises on an invalid action" do
    archive_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :archive_project_item, arguments: { "repositoryId" => 123 })

    assert_raises_with_message(ArgumentError, "action must be of type :add_project_item") do
      run_workflow(action: archive_items_action, input: [@issue_item, @pull_request_item])
    end
  end

  context "item already added" do
    test "does not raise" do
      refute @project.memex_project_items.any? { |item| item.content == @issue }
      item = @project.build_item(issue_or_pull: @issue, creator: Apps::Privileged::MemexAutomation.bot)
      @project.save_with_priority!(item, **{ position: :bottom })
      assert @project.memex_project_items.any? { |item| item.content == @issue }

      run_workflow(action: @add_items_action, input: [@issue])

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
        tags: [
          "trigger_type:query_matched",
          "runner:piped",
          "action_type:add_project_item",
          "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_RECORD_INVALID}",
        ] + @tags
      )
    end

    test "does not raise when ActiveRecord::RecordNotUnique is thrown" do
      MemexProject.any_instance.stubs(:save_with_priority!).raises(ActiveRecord::RecordNotUnique.new(""))

      run_workflow(action: @add_items_action, input: [@issue])

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
        tags: [
          "trigger_type:query_matched",
          "runner:piped",
          "action_type:add_project_item",
          "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_EXISTS}",
        ] + @tags
      )
    end
  end
end
