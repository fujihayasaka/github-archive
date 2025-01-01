# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventProjectsV2ItemEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @repo = create(:public_repository, owner: @org)
    @issue = create(:issue, repository: @repo, user: @admin)
    @actor = create(:user, login: "actor")
    @project = create(:memex_project, owner: @org, title: "My Memex Project")
    @item = create(:memex_project_item, memex_project: @project, content: @issue)
    @column = create(:memex_project_column, memex_project: @project, data_type: :title)
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :edited, item: @item, column: @column, actor: @actor, changes: nil)
    Hook::Event::ProjectsV2ItemEvent.new(
      action: action,
      memex_project_item_id: item.id,
      changed_field_id: column.id,
      actor_id: actor.id,
      organization_id: item.memex_project.organization_owner_id,
      changes: changes
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ProjectsV2ItemEvent, :action, :memex_project_item_id, :organization_id, :actor_id
  end

  context "#item" do
    test "returns a MemexProjectItem" do
      event = create_event
      assert_equal @item, event.item
    end

    test "returns nil if the project item no longer exists" do
      event = create_event
      @item.destroy!

      assert_nil event.item
    end
  end

  context "#project" do
    test "returns the project item's parent MemexProject" do
      event = create_event
      assert_equal @project, event.project
    end

    test "returns nil if the project no longer exists" do
      event = create_event
      @project.destroy!

      assert_nil event.project
    end
  end

  context "#actor" do
    test "returns a User" do
      event = create_event
      assert_equal @actor, event.actor
    end

    test "returns nil actor no longer exists" do
      event = create_event
      @actor.destroy!

      assert_nil event.actor
    end
  end

  context "#target_organization" do
    test "returns an Organization" do
      event = create_event
      assert_equal @org, event.target_organization
    end

    test "returns nil when the org no longer exists" do
      event = create_event
      @org.destroy!

      assert_nil event.target_organization
    end
  end

  context "#deliverable?" do
    test "returns true if item, parent project, and project owner are all present" do
      event = create_event
      assert_predicate event, :deliverable?
    end

    test "returns false if the project owner is missing" do
      event = create_event
      @org.destroy!

      refute_predicate event, :deliverable?
    end

    test "returns false if the item's parent project is missing" do
      event = create_event
      @project.destroy!

      refute_predicate event, :deliverable?
    end

    test "returns false if the item is missing" do
      event = create_event
      @item.destroy!

      refute_predicate event, :deliverable?
    end

    test "returns false if the item's content is missing" do
      event = create_event
      @item.content.destroy!

      refute_predicate event, :deliverable?
    end
  end

  context "#changed_values" do
    test "returns changed_values if present in the changes hash" do
      column = create(:memex_project_column, memex_project: @project, data_type: :text)
      changes = { "value" => %w(old new) }
      event = create_event(action: :edited, column: column, changes: changes)
      assert_equal %w(old new), event.changed_values
    end

    test "returns nil if only one value is present" do
      changes = { "value" => ["old"] }
      event = create_event(action: :edited, changes: changes)
      assert_nil event.changed_values
    end

    test "returns nil when there are no changes" do
      event = create_event(action: :edited)
      assert_nil event.changed_values
    end
  end

  context "#edited?" do
    test "returns true if the current event action is :edited" do
      event = create_event(action: :edited)
      assert_predicate event, :edited?
    end

    test "returns true if the current event action is 'edited'" do
      event = create_event(action: "edited")
      assert_predicate event, :edited?
    end

    test "returns false if the current event action isn't :edited" do
      event = create_event(action: "converted")
      refute_predicate event, :edited?
    end
  end

  context "#changes" do
    test "includes changed field_node_id and field_type for edited events" do
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: @column.id, organization_id: @org.id, actor_id: @actor.id)

      assert_equal event.changes[:field_value][:field_node_id], @column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], @column.data_type
      assert_equal event.changes[:field_value][:field_name], @column.name
      assert_equal event.changes[:field_value][:project_number], @column.memex_project.number
    end

    test "includes changed from and to for edited events w/ generic_type columns" do
      # This column (text) is a generic type
      generic_type_column = create(:memex_project_column, memex_project: @project, data_type: :text)
      changes = { "value" => %w(old new) }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: generic_type_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], generic_type_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], generic_type_column.data_type
      assert_equal event.changes[:field_value][:field_name], generic_type_column.name
      assert_equal event.changes[:field_value][:project_number], generic_type_column.memex_project.number
      assert_equal "old", event.changes[:field_value][:from]
      assert_equal "new", event.changes[:field_value][:to]
    end

    test "includes changed from/to for edited events w/ single select settings" do
      single_select_column = create(:single_select_memex_column, memex_project: @project)
      from = single_select_column.settings["options"][0]["id"]
      to = single_select_column.settings["options"][1]["id"]
      changes = { "value" => [from, to] }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: single_select_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], single_select_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], single_select_column.data_type
      assert_equal event.changes[:field_value][:field_name], single_select_column.name
      assert_equal event.changes[:field_value][:project_number], single_select_column.memex_project.number
      assert_equal single_select_column.settings["options"][0]&.slice("id", "name", "color", "description"), event.changes[:field_value][:from]
      assert_equal single_select_column.settings["options"][1]&.slice("id", "name", "color", "description"), event.changes[:field_value][:to]
    end

    test "excludes changed from/to for edited events when single select settings options can't be found" do
      single_select_column = create(:single_select_memex_column, memex_project: @project)
      from = single_select_column.settings["options"][0]["id"]
      to = single_select_column.settings["options"][1]["id"] + "-deleted"
      changes = { "value" => [from, to] }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: single_select_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], single_select_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], single_select_column.data_type
      assert_equal event.changes[:field_value][:field_name], single_select_column.name
      assert_equal event.changes[:field_value][:project_number], single_select_column.memex_project.number
      assert_equal single_select_column.settings["options"][0]&.slice("id", "name", "color", "description"), event.changes[:field_value][:from]
      assert_nil event.changes[:field_value][:to]
    end

    test "includes changed from/to for edited events w/ iteration configs" do
      iteration_column = create(:iteration_memex_column, memex_project: @project)

      from = iteration_column.settings_iterations[0]["id"]
      to = iteration_column.settings_iterations[1]["id"]
      changes = { "value" => [from, to] }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: iteration_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], iteration_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], iteration_column.data_type
      assert_equal event.changes[:field_value][:field_name], iteration_column.name
      assert_equal event.changes[:field_value][:project_number], iteration_column.memex_project.number
      assert_equal iteration_column.settings_iterations[0]&.slice("id", "title", "duration", "start_date"), event.changes[:field_value][:from]
      assert_equal iteration_column.settings_iterations[1]&.slice("id", "title", "duration", "start_date"), event.changes[:field_value][:to]
    end

    test "includes changed from/to for edited events with completed iterations" do
      iteration_column = create(:iteration_memex_column_with_completed, memex_project: @project)

      from = iteration_column.settings_iterations[0]["id"]
      to = iteration_column.settings_completed_iterations[0]["id"]
      changes = { "value" => [from, to] }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: iteration_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], iteration_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], iteration_column.data_type
      assert_equal event.changes[:field_value][:field_name], iteration_column.name
      assert_equal event.changes[:field_value][:project_number], iteration_column.memex_project.number
      assert_equal iteration_column.settings_iterations[0]&.slice("id", "title", "duration", "start_date"), event.changes[:field_value][:from]
      assert_equal iteration_column.settings_completed_iterations[0]&.slice("id", "title", "duration", "start_date"), event.changes[:field_value][:to]
    end

    test "excludes changed from/to for edited events when iteration configs can't be found" do
      iteration_column = create(:iteration_memex_column, memex_project: @project)

      from = iteration_column.settings_iterations[0]["id"]
      to = iteration_column.settings_iterations[1]["id"] + "-deleted"
      changes = { "value" => [from, to] }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: iteration_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], iteration_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], iteration_column.data_type
      assert_equal event.changes[:field_value][:field_name], iteration_column.name
      assert_equal event.changes[:field_value][:project_number], iteration_column.memex_project.number
      assert_equal iteration_column.settings_iterations[0]&.slice("id", "title", "duration", "start_date"), event.changes[:field_value][:from]
      assert_nil event.changes[:field_value][:to]
    end

    test "excludes changed from and to for edited events w/ special_type columns" do
      # This column (title) is a special type
      special_type_column = create(:memex_project_column, memex_project: @project, data_type: :title)
      changes = { "value" => %w(old new) }
      event = Hook::Event::ProjectsV2ItemEvent.new(action: :edited, memex_project_item_id: @item.id, changed_field_id: special_type_column.id, organization_id: @org.id, actor_id: @actor.id, changes: changes)

      assert_equal event.changes[:field_value][:field_node_id], special_type_column.global_relay_id
      assert_equal event.changes[:field_value][:field_type], special_type_column.data_type
      assert_equal event.changes[:field_value][:field_name], special_type_column.name
      assert_equal event.changes[:field_value][:project_number], special_type_column.memex_project.number
      assert_nil event.changes[:field_value][:from]
      assert_nil event.changes[:field_value][:to]
    end
  end
end
