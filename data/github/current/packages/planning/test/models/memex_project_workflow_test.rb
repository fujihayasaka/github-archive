# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowTest < GitHub::TestCase
  fixtures do
    @project = create(:memex_project)
    @repo = create(:repository, owner: @project.owner)
  end

  setup do
    GitHub.flipper[:memex_workflow_actions_validator_kill_switch].disable
  end

  def create_invalid_workflow
    get_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:open", "repositoryId" => 123 })
    get_project_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_project_items, arguments: { "query" => "is:closed" })
    archive_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :archive_project_item, arguments: {})
    actions = [get_items_action, get_project_items_action, archive_items_action]

    build(:memex_project_workflow, :skip_validations, name: "Invalid Item Added Workflow", enabled: true, actions: actions, trigger_type: :item_added)
  end


  context "validations" do
    test "requires a project" do
      workflow = build(:memex_project_workflow, memex_project: nil)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Memex project can't be blank"
    end

    test "requires a number" do
      workflow = build(:memex_project_workflow, number: nil)
      workflow.stubs(:set_number) # Make the default setter a no-op.

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Number can't be blank"
    end

    test "requires that number is a positive integer" do
      workflow = build(:memex_project_workflow, number: -1)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Number must be greater than 0"

      workflow.number = 0.5
      refute workflow.save
      assert_includes workflow.errors.full_messages, "Number must be an integer"
    end

    test "requires that number is unique per project" do
      existing_workflow = create(:memex_project_workflow)
      new_workflow = build(
        :memex_project_workflow,
        memex_project: existing_workflow.memex_project,
        number: existing_workflow.number
      )

      refute new_workflow.save
      assert_includes new_workflow.errors.full_messages, "Number has already been taken"
    end

    test "sets a number by default" do
      workflow = build(:memex_project_workflow, number: nil)
      workflow.save!

      refute_nil workflow.reload.number
    end

    test "requires a creator on create" do
      workflow = build(:memex_project_workflow, creator: nil)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Creator can't be blank"
    end

    test "does not require a creator on update" do
      user = create(:verified_user)
      workflow = create(:memex_project_workflow, creator: user)

      assert user.destroy!
      assert workflow.reload
      assert_nil workflow.creator, "should not locate a user for the creator association"
      assert_equal user.id, workflow.creator_id, "creator_id should still be set to the user's id"
      assert workflow.save, "workflow should still be valid"
    end

    test "requires a last updater" do
      workflow = build(:memex_project_workflow)
      workflow.stubs(:set_last_updater) # Make the default setter a no-op.

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Last updater can't be blank"
    end

    test "sets last updater to ghost user on update if original last updater is gone" do
      user = create(:verified_user)
      workflow = create(:memex_project_workflow, last_updater: user)

      assert user.destroy!
      assert workflow.reload
      assert_nil workflow.last_updater, "should not locate a user for the last_updater association"
      assert_equal user.id, workflow.last_updater_id, "last_updater_id should still be set to the user's id"
      assert workflow.save
      assert_equal User.ghost, workflow.reload.last_updater, "last_updater should be set to the ghost user"
    end

    test "sets last updater to actor from context on update if original last updater is gone" do
      user = create(:verified_user)
      actor = create(:verified_user)
      workflow = create(:memex_project_workflow, last_updater: user)

      assert user.destroy!
      assert workflow.reload
      assert_nil workflow.last_updater, "should not locate a user for the last_updater association"
      assert_equal user.id, workflow.last_updater_id, "last_updater_id should still be set to the user's id"
      GitHub.context.push(actor: actor) do
        assert workflow.save
      end
      assert_equal actor, workflow.reload.last_updater, "last_updater should be set to the actor user from context"
    end

    test "sets last updater by default" do
      workflow = build(:memex_project_workflow, last_updater: nil)
      workflow.save!

      refute_nil workflow.reload.last_updater_id
    end

    test "requires a name" do
      workflow = build(:memex_project_workflow, name: nil)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Name can't be blank"
    end

    test "requires that name cannot exceed a certain length" do
      workflow = build(:memex_project_workflow, name: "x" * (MemexProjectWorkflow::NAME_CHARACTER_LIMIT + 1))

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Name is too long (maximum is 63 characters)"
    end

    test "allows emoji in the name" do

      workflow = build(:memex_project_workflow, name: "🏅")
      assert workflow.save
      assert_equal "🏅", workflow.reload.name
    end

    test "requires that name is unique per project" do
      get_issues_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:open", "repositoryId" => @repo.id })
      add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })

      existing_workflow = create(:memex_project_workflow,
        name: "Add Item on Issue Create",
        memex_project: @project,
        actions: [get_issues_action, add_items_action],
        trigger_type: :query_matched,
      )

      new_workflow = build(:memex_project_workflow,
        name: existing_workflow.name,
        memex_project: existing_workflow.memex_project,
        actions: [get_issues_action, add_items_action],
        trigger_type: :query_matched,
      )

      refute new_workflow.save
      assert_includes new_workflow.errors.full_messages, "A workflow with the name \"#{existing_workflow.name}\" already exists"
    end

    test "does not allow duplicate workflows with same query for a repository" do

      get_issues_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "-milestone:test label:blah,\"🐛\" is:pr,issue is:open", "repositoryId" => @repo.id })
      add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })

      existing_workflow = create(:memex_project_workflow,
        name: "Add Item on Issue Create",
        memex_project: @project,
        actions: [get_issues_action, add_items_action],
        trigger_type: :query_matched,
      )

      get_issues_action_2 = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:pr is:open -milestone:test label:blah label:\"🐛\"", "repositoryId" => @repo.id })
      add_items_action_2 = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })

      new_workflow = build(:memex_project_workflow,
        name: existing_workflow.name,
        memex_project: existing_workflow.memex_project,
        actions: [get_issues_action_2, add_items_action_2],
        trigger_type: :query_matched,
      )

      refute new_workflow.save
      assert_includes new_workflow.errors.full_messages, "The \"#{existing_workflow.name}\" workflow already matches this query and repository"
    end

    test "allows renaming workflow with same query for a repository" do
      get_issues_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "-milestone:test label:blah,\"🐛\" is:pr,issue is:open", "repositoryId" => @repo.id })
      add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })

      original_name = "Add Item on Issue Create"

      workflow = create(:memex_project_workflow,
        name: original_name,
        memex_project: @project,
        actions: [get_issues_action, add_items_action],
        trigger_type: :query_matched,
      )

      workflow.name = "New Name"

      assert workflow.save
      refute_includes workflow.errors.full_messages, "The \"#{original_name}\" workflow already matches this query and repository"
    end

    test "requires a trigger type" do
      workflow = build(:memex_project_workflow, trigger_type: nil)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Trigger type can't be blank"
    end

    test "requires an enabled boolean" do
      workflow = build(:memex_project_workflow, enabled: nil)
      workflow.stubs(:set_enabled_to_false_by_default) # Make the default setter a no-op.

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Enabled must be true or false"
    end

    test "sets enabled to false by default" do
      workflow = build(:memex_project_workflow, enabled: nil)
      workflow.save!

      assert_equal false, workflow.reload.enabled
    end

    test "requires content types" do
      workflow = build(:memex_project_workflow, content_types: nil)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types can't be blank"

      workflow.content_types = []
      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types can't be blank"
    end

    test "requires that content types are valid for the 'item_added' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue DraftIssue], trigger_type: :item_added)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): DraftIssue"
    end

    test "requires that content types are valid for the 'reopened' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue DraftIssue], trigger_type: :reopened)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): DraftIssue"
    end

    test "requires that content types are valid for the 'review_changes_requested' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue PullRequest], trigger_type: :review_changes_requested)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): Issue"
    end

    test "requires that content types are valid for the 'review_approved' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue PullRequest], trigger_type: :review_approved)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): Issue"
    end

    test "requires that content types are valid for the 'closed' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue DraftIssue])

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): DraftIssue"
    end

    test "requires that content types are valid for the 'merged' trigger type" do
      workflow = build(:memex_project_workflow, content_types: %w[Issue PullRequest], trigger_type: :merged)

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Content types contains invalid value(s): Issue"
    end

    test "requires that actions are a valid combination when kill switch is disabled" do
      GitHub.flipper[:memex_workflow_actions_validator_kill_switch].disable

      workflow = create_invalid_workflow

      refute workflow.save
      assert_includes workflow.errors.full_messages, "Actions must be a valid combination"
    end

    test "does not require that actions are a valid combination when kill switch is enabled" do
      GitHub.flipper[:memex_workflow_actions_validator_kill_switch].enable

      workflow = create_invalid_workflow

      assert workflow.save
      refute_includes workflow.errors.full_messages, "Actions must be a valid combination"
    end
  end

  context ".default_item_added_workflow_attributes" do
    test "returns valid default attributes for an 'item_added' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_item_added_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_item_added_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end
  end

  context ".default_reopened_workflow_attributes" do
    test "returns valid default attributes for a 'reopened' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_reopened_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_reopened_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end

    test "uses second option in status column settings if at least two options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
            { id: "bbbbbbbb", name: "medium", name_html: "medium", color: "ORANGE", description: "", description_html: "" },
            { id: "cccccccc", name: "large", name_html: "large", color: "BLUE", description: "", description_html: "" },
            { id: "dddddddd", name: "xlarge", name_html: "xlarge", color: "GREEN", description: "should probably be broken down", description_html: "should probably be broken down" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_reopened_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "bbbbbbbb"
    end

    test "uses first option in status column settings if only one" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_reopened_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "aaaaaaaa"
    end
  end

  context ".default_review_changes_requested_workflow_attributes" do
    test "returns valid default attributes for a 'review_changes_requested' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_changes_requested_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_review_changes_requested_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end

    test "uses second option in status column settings if at least two options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
            { id: "bbbbbbbb", name: "medium", name_html: "medium", color: "RED", description: "", description_html: "" },
            { id: "cccccccc", name: "large", name_html: "large", color: "BLUE", description: "", description_html: "" },
            { id: "dddddddd", name: "xlarge", name_html: "xlarge", color: "RED", description: "should probably be broken down", description_html: "should probably be broken down" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_changes_requested_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "bbbbbbbb"
    end

    test "uses first option in status column settings if only one" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_changes_requested_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "aaaaaaaa"
    end
  end

  context ".default_review_approved_workflow_attributes" do
    test "returns valid default attributes for a 'review_approved' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_approved_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_review_approved_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end

    test "uses second option in status column settings if at least two options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
            { id: "bbbbbbbb", name: "medium", name_html: "medium", color: "RED", description: "", description_html: "" },
            { id: "cccccccc", name: "large", name_html: "large", color: "BLUE", description: "", description_html: "" },
            { id: "dddddddd", name: "xlarge", name_html: "xlarge", color: "RED", description: "should probably be broken down", description_html: "should probably be broken down" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_approved_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "bbbbbbbb"
    end

    test "uses first option in status column settings if only one" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update!(settings:
        {
          "options": [
            { id: "aaaaaaaa", name: "small", name_html: "small", color: "RED", description: "", description_html: "" },
          ]
        }
      )

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_review_approved_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
      assert_equal workflow.actions[0].arguments["fieldOptionId"], "aaaaaaaa"
    end
  end

  context ".default_closed_workflow_attributes" do
    test "returns valid default attributes for a 'closed' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end
  end

  context ".default_merged_workflow_attributes" do
    test "returns valid default attributes for a 'merged' workflow" do
      project = create(:memex_project)

      workflow = project.workflows.build(
        MemexProjectWorkflow.default_merged_workflow_attributes(
          status_column: project.status_column,
          creator: create(:user)
        )
      )

      assert workflow.save
    end

    test "raises if the provided status column has no options" do
      project = create(:memex_project)
      status_column = project.status_column
      status_column.update_attribute("settings", nil)

      assert_raises(ArgumentError) do
        MemexProjectWorkflow.default_merged_workflow_attributes(
          status_column: status_column,
          creator: create(:user)
        )
      end
    end
  end

  context "#to_hash" do
    test "returns a representation of the workflow for the internal API" do
      workflow = create(:memex_project_workflow)
      refute_empty workflow.actions

      assert_equal(
        {
          id: workflow.id,
          name: workflow.name,
          number: workflow.number,
          triggerType: workflow.trigger_type,
          contentTypes: workflow.content_types,
          enabled: workflow.enabled,
          actions: workflow.actions.map(&:to_hash),
        },
        workflow.to_hash,
      )
    end
  end

  context "set_number" do
    test "uses a unique sequence scoped to the memex project for numbering" do
      # The first workflow created should be numbered starting from 1
      workflow = create(:memex_project_workflow)
      assert_equal workflow.memex_project.workflows.count, 1
      assert_equal workflow.number, 1

      # Create a view
      initial_view_count = workflow.memex_project.memex_project_views.count
      create(:memex_project_view, memex_project: workflow.memex_project)
      assert_equal workflow.memex_project.memex_project_views.count, initial_view_count + 1

      # Create a chart
      create(:memex_project_chart, memex_project: workflow.memex_project)
      assert_equal workflow.memex_project.charts.count, 1

      # The second workflow created should be numbered 2, independent of other entities that
      # were just created
      new_workflow = create(:memex_project_workflow, memex_project: workflow.memex_project, name: "🚢 Ship it", trigger_type: :item_added)
      assert_equal new_workflow.number, 2
    end

    test "it uses a unique workflow sequence per memex_project" do
      memex_project_1 = create(:memex_project)
      memex_project_2 = create(:memex_project)
      refute_equal memex_project_1.id, memex_project_2.id

      workflow_1 = create(:memex_project_workflow, memex_project: memex_project_1)
      workflow_2 = create(:memex_project_workflow, memex_project: memex_project_2)

      assert_equal workflow_1.number, 1
      assert_equal workflow_2.number, 1
    end

    test "For workflows that previously used the shared sequence, it continues the numbering with the next available number \
      but uses the new sequence" do
      # To simulate this being a workflow that was created with the shared sequence,
      # we will pass in a number to avoid the new (MemexProjectWorkflow, memex_project.id) sequence from being created
      workflow_1 = create(:memex_project_workflow, number: 2)
      assert_equal workflow_1.memex_project.workflows.count, 1
      assert_equal workflow_1.number, 2

      # Create a second workflow. It should be numbered 3
      workflow_2 = create(:memex_project_workflow, memex_project: workflow_1.memex_project, name: "🚢 Ship it", trigger_type: :item_added)
      assert_equal workflow_2.number, 3

      # A (MemexProjectWorkflow, memex_project.id) sequence should be created with the correct default
      ApplicationRecord::Domain::Sequences.table_name = "sequences"
      workflow_sequence = ApplicationRecord::Domain::Sequences.find_by(context_type: "MemexProjectWorkflow", context_id: workflow_1.memex_project.id)
      refute_nil workflow_sequence
      assert_equal workflow_sequence.number, 3
    end
  end
end
