# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorklowActionArgumentValidator < GitHub::TestCase

  fixtures do
    @memex = create(:memex_project)
    @status_column = @memex.status_column
    @status_option = @status_column.settings_options.last
  end

  def validator
    MemexProjectWorkflowAction::ArgumentValidator.new
  end

  test "requires that arguments are a hash" do
    action = build(:memex_project_workflow_action, arguments: [], skip_argument_build: true)
    validator.validate(action)
    assert_includes action.errors.full_messages, "Arguments must be a Hash"
  end

  context "set_field action" do
    test "requires fieldId for a set_field action" do
      action = build(
        :memex_project_workflow_action,
        action_type: :set_field,
        arguments: {
          fieldOptionId: @status_option["id"]
        },
        skip_argument_build: true
      )

      validator.validate(action)

      assert_includes action.errors.full_messages, "Arguments must include a 'fieldId' value"
    end

    test "requires that fieldId reference for a set_field action exists" do
      memex = create(:memex_project)
      status_column = memex.status_column
      status_option = status_column.settings_options.last
      status_column.destroy!

      action = build(
        :memex_project_workflow_action,
        action_type: :set_field,
        arguments: {
          fieldId: status_column.id,
          fieldOptionId: status_option["id"],
        },
        skip_argument_build: true
      )

      validator.validate(action)

      assert_includes action.errors.full_messages, "Field argument can't be blank"
    end

    test "requires a workflow for a set_field action" do
      memex = create(:memex_project)
      status_column = memex.status_column
      status_option = status_column.settings_options.last

      action = build(
        :memex_project_workflow_action,
        action_type: :set_field,
        arguments: {
          fieldId: status_column.id,
          fieldOptionId: status_option["id"],
        },
        skip_argument_build: true
      )

      action.workflow = nil
      validator.validate(action)

      assert_includes action.errors.full_messages, "Field argument can't be blank"
    end

    test "requires that fieldId for a set_field action references a single-select column" do
      action = build(:memex_project_workflow, memex_project: @memex).actions.first
      action.arguments["fieldId"] = @memex.columns.find(&:assignees?).id

      validator.validate(action)

      assert_includes action.errors.full_messages, "Field argument must be of type single-select"
    end

    test "does not require fieldOptionId for a set_field action" do
      workflow = build(:memex_project_workflow, memex_project: @memex)
      action = build(
        :memex_project_workflow_action,
        workflow: workflow,
        action_type: :set_field,
        arguments: {
          fieldId: @status_column.id
        },
        skip_argument_build: true
      )

      validator.validate(action)
      assert action.valid?
    end

    test "requires that fieldOptionId reference for a set_field action exists" do
      memex = create(:memex_project)
      status_column = memex.status_column
      status_option = status_column.settings_options.last
      action = build(:memex_project_workflow, memex_project: memex).actions.first

      # Delete the option that was referenced in the above action.
      status_column.settings["options"].pop
      status_column.save!

      validator.validate(action)

      assert_includes action.errors.full_messages, "Field option argument must match an existing option"
    end
  end

  context "get_project_items action" do
    test "requires non-empty query" do
      action = build(
        :memex_project_workflow_action,
        action_type: :get_project_items,
        arguments: {
          query: ""
        },
        skip_argument_build: true
      )

      validator.validate(action)

      assert_includes action.errors.full_messages, "Query argument can't be blank"
    end
  end

  context "get_items action" do
    test "requires a repository id but allows excluding query" do
      action = build(
        :memex_project_workflow_action,
        action_type: :get_items,
        arguments: {},
        skip_argument_build: true
      )

      validator.validate(action)

      refute_includes action.errors.full_messages, "Query argument can't be blank"
      assert_includes action.errors.full_messages, "Repository argument can't be blank"
    end

    test "requires valid query tokens" do
      action = build(
        :memex_project_workflow_action,
        action_type: :get_items,
        arguments: {
          query: "foo:bar",
          repositoryId: 123
        },
        skip_argument_build: true
      )

      validator.validate(action)

      assert_includes action.errors.full_messages, "Query argument contains invalid tokens: foo:bar"
    end

    test "allows emoji shortcodes in quoted queries" do
      action = build(
        :memex_project_workflow_action,
        action_type: :get_items,
        arguments: {
          query: 'label:"bug :beetle:"',
          repositoryId: 123
        },
        skip_argument_build: true
      )

      validator.validate(action)

      assert_empty action.errors.full_messages
      assert action.valid?
    end
  end

  context "add_project_item" do
    test "requires a repository id" do
      action = build(
        :memex_project_workflow_action,
        action_type: :add_project_item,
        arguments: {},
        skip_argument_build: true
      )

      validator.validate(action)

      assert_includes action.errors.full_messages, "Repository argument can't be blank"
    end
  end
end
