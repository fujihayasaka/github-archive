# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectStructureSerializerTest < GitHub::TestCase
  include PrioritizationHelpers

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization)

    @memex  = create(:memex_project, owner: @org, title: "A Feature Template Memex")

    # N.B. the way `apply_default_template` works, a project is created *with default fields* and then
    # fields in the template are *added* to it. Keep this in mind through the assertions below, as we're
    # asserting against the project *as modified by the template* rather than the template itself.
    @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate)

    @layout_settings_memex = create(:memex_project, owner: @org, title: "A Memex with a Roadmap View")
    @board_view = create(
      :memex_project_view,
      layout: "board_layout",
      memex_project: @layout_settings_memex,
      priority: 1,
    )
    @start_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "Start Date", memex_project: @layout_settings_memex)
    @end_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "End Date", memex_project: @layout_settings_memex)
    @other_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "Other Date", memex_project: @layout_settings_memex)
    @roadmap_view = create(:memex_project_view, layout: "roadmap_layout", memex_project: @layout_settings_memex, priority: 2, visible_fields: [@start_date_field.id, @end_date_field.id])
    @roadmap_view.update_attribute(:layout_settings, {
      roadmap: {
        date_fields: [@start_date_field.id, @end_date_field.id],
        marker_fields: [@start_date_field.id, @end_date_field.id, @other_date_field.id]
      }
    })
  end

  def test_columns_match
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    assert_equal @memex.memex_project_columns.length, serialized_memex[:columns].length

    @memex.memex_project_columns.each_with_index do |column, index|
      assert_equal column.data_type, @memex.memex_project_columns[index].data_type
      assert_equal column.name, serialized_memex[:columns][index][:name]
      assert_equal column.visible, serialized_memex[:columns][index][:visible]
    end
  end

  def test_statuses_match
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    status_column_options = @memex.status_column.settings["options"]

    serialized_status_column = serialized_memex[:columns].find { |c| c[:name] == MemexProjectColumn::STATUS_COLUMN_NAME }
    serialized_status_column_options = serialized_status_column[:settings][:options]

    status_column_options.each do |option|
      serialized_option = serialized_status_column_options.find { |o| o["name"] == option["name"] }
      refute_nil serialized_option
      assert_equal option.except!("id", "name_html", "description_html"), serialized_option.except!("id", "name_html", "description_html")
    end
  end

  def test_single_select_options_defaults
    options = [
      { name: "foo", color: "RED", description: "foo description" },
      { name: "baz", color: "BLUE", description: "baz description" },
    ]

    column = create(
      :memex_project_column,
      data_type: :single_select,
      settings: {
        "width" => 600,
        "options" => options
      }
    )

    column.settings["options"][1].delete("color")
    column.settings["options"][1].delete("description")

    # use .send to access private method
    result = MemexProject::StructureSerializer.new(@memex).send(:filtered_settings, column)

    assert_equal column.settings["options"][0], result["options"][0]
    assert_equal column.settings["options"][1]["name"], result["options"][1]["name"]
    # preserve option ids when template is copied
    assert_equal column.settings["options"][1]["id"], result["options"][1]["id"]
    assert_equal "GRAY", result["options"][1]["color"]
    assert_equal "", result["options"][1]["description"]
  end

  def test_iteration_column_ids_match
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    iteration_column = @memex.columns.find { |c| c.name == "Iteration" }
    serialized_iteration_column = serialized_memex[:columns].find { |c| c[:name] == "Iteration" }

    # we preserve iteration ids to ensure that copied draft issues will have the same iteration
    assert_equal iteration_column.settings["configuration"]["iterations"][0]["id"], serialized_iteration_column[:settings]["configuration"]["iterations"][0]["id"]
  end

  def test_views_match
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    assert_equal @memex.memex_project_views.length, serialized_memex[:views].length
    @memex.memex_project_views.each_with_index do |view, index|
      assert_equal view.name, serialized_memex[:views][index][:name]
      assert_equal view.layout.to_sym, serialized_memex[:views][index][:layout]
    end
  end

  def test_view_serialization_respects_order
    assert_equal ["Home", "Current iteration", "Next iteration", "Planning"], @memex.memex_project_views.sort_by(&:priority).map(&:name)

    current_view = @memex.memex_project_views.first # Home
    view_to_reprioritize = @memex.memex_project_views.last # Planning

    allow_transaction_nesting do
      # Move the Planning view before the Home view
      @memex.save_view_with_priority!(view_to_reprioritize, **{ after: current_view })
    end

    serialized_memex = MemexProject::StructureSerializer.new(@memex.reload).serialize
    assert_equal ["Planning", "Home", "Current iteration", "Next iteration"], serialized_memex[:views].map { |view| view[:name] }

    # Ensure serialization does not break with null priority
    current_view.update(priority: nil)

    serialized_memex = MemexProject::StructureSerializer.new(@memex.reload).serialize
    assert_equal ["Home", "Planning", "Current iteration", "Next iteration"], serialized_memex[:views].map { |view| view[:name] }
  end

  def test_views_group_by
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    @memex.memex_project_views.each_with_index do |view, index|
      view.group_by.each do |field_id|
        field_name = @memex.memex_project_columns.find(field_id).name_slug
        assert serialized_memex[:views][index][:group_by_fields_by_name].include? field_name
      end
    end
  end

  def test_views_sort_by
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    @memex.memex_project_views.each_with_index do |view, index|
      view.sort_by.each do |field_id_and_order|
        field_id, order = field_id_and_order
        field_name = @memex.memex_project_columns.find(field_id).name_slug
        assert_equal field_id_and_order, serialized_memex[:views][index][:sort_by_fields_by_name]
      end
    end
  end

  def test_views_visible_fields
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    @memex.memex_project_views.each_with_index do |view, index|
      view.visible_fields.each do |field_id|
        field_name = @memex.memex_project_columns.find(field_id).name_slug
        assert serialized_memex[:views][index][:visible_fields_by_name].include? field_name
      end
    end
  end

  def test_board_views_column_field
    # Change the column field to "Iteration"
    iteration_column = @memex.memex_project_columns.find_by(name: "Iteration")
    board_view = @memex.memex_project_views.find_by(name: "Current iteration")
    board_view.update_attribute(:vertical_group_by, [iteration_column.id])

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize

    serialized_current_iteration_view = serialized_memex[:views].find { |v| v[:name] == "Current iteration" }
    assert_equal ["iteration"], serialized_current_iteration_view[:column_field_by_name]
  end

  def test_view_slice_by_field
    iteration_column = @memex.memex_project_columns.find_by(name: "Iteration")
    board_view = @memex.memex_project_views.find_by(name: "Current iteration")
    board_view.update_attribute(:slice_by, { "field" => iteration_column.id, "panel_width" => 500, "filter" => "abc" })

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_current_iteration_view = serialized_memex[:views].find { |v| v[:name] == "Current iteration" }

    expected_slice_by = {
      panel_width: 500,
      filter: "abc",
      field_name: "iteration"
    }

    assert_equal expected_slice_by, serialized_current_iteration_view[:slice_by_field_by_name]
  end

  def test_view_invalid_slice_by_field
    board_view = @memex.memex_project_views.find_by(name: "Current iteration")
    board_view.update_attribute(:slice_by, { "field" => -1, "panel_width" => 500, "filter" => "abc" })

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_current_iteration_view = serialized_memex[:views].find { |v| v[:name] == "Current iteration" }

    assert_equal ({}), serialized_current_iteration_view[:slice_by_field_by_name]
  end

  def test_board_views_layout_settings_status
    status_column = @layout_settings_memex.status_column
    todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"].to_s

    @board_view.update_attribute(:vertical_group_by, [status_column.id])
    @board_view.update_attribute(:layout_settings, {
      board: {
        column_limits: {
          "#{status_column.id}" => {
            "#{todo_option_id}" => 10
          }
        }
      }
    })
    serialized_memex = MemexProject::StructureSerializer.new(@layout_settings_memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:name] == @board_view.name }

    assert_column_limit(
      serialized_view: serialized_view,
      column_slug: "status",
      option_id: todo_option_id,
      column_limit: 10
    )
  end

  def test_board_views_layout_settings_single_select
    options = [
      { name: "foo", color: "RED", description: "foo description" },
      { name: "baz", color: "BLUE", description: "baz description" },
    ]

    column = create(
      :memex_project_column,
      name: "Custom single-select",
      memex_project: @layout_settings_memex,
      data_type: :single_select,
      settings: {
        "width" => 600,
        "options" => options
      }
    )

    foo_option_id = column.settings["options"].find { |o| o["name"] == "foo" }["id"].to_s
    @board_view.update_attribute(:vertical_group_by, [column.id])
    @board_view.update_attribute(:layout_settings, {
      board: {
        column_limits: {
          "#{column.id}" => {
            "#{foo_option_id}" => 20
          }
        }
      }
    })

    serialized_memex = MemexProject::StructureSerializer.new(@layout_settings_memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:name] == @board_view.name }

    assert_column_limit(
      serialized_view: serialized_view,
      column_slug: "custom-single-select",
      option_id: foo_option_id,
      column_limit: 20
    )
  end

  def test_board_views_layout_settings_iteration
    column = @memex.memex_project_columns.find_by(name: "Iteration")
    board_view = @memex.memex_project_views.find_by(name: "Current iteration")
    iteration_option_id = column.settings["configuration"]["iterations"].find { |o| o["title"] == "Iteration" }["id"].to_s
    board_view.update_attribute(:vertical_group_by, [column.id])
    board_view.update_attribute(:layout_settings, {
      board: {
        column_limits: {
          "#{column.id}" => {
            "#{iteration_option_id}" => 30
          }
        }
      }
    })

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:name] == board_view.name }

    assert_column_limit(
      serialized_view: serialized_view,
      column_slug: "iteration",
      option_id: iteration_option_id,
      column_limit: 30
    )
  end

  def test_roadmap_views_layout_settings_date_fields
    serialized_memex = MemexProject::StructureSerializer.new(@layout_settings_memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:layout] == :roadmap_layout }

    assert_equal %w[start-date end-date], serialized_view[:layout_settings_by_name]["roadmap"]["date_fields"]
  end

  def test_roadmap_views_layout_settings_marker_fields
    serialized_memex = MemexProject::StructureSerializer.new(@layout_settings_memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:layout] == :roadmap_layout }

    assert_equal %w[start-date end-date other-date], serialized_view[:layout_settings_by_name]["roadmap"]["marker_fields"]
  end

  def test_workflows_include_configuration
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_workflow = serialized_memex[:workflows].find { |w| w[:trigger_type] == "closed" }

    assert_equal serialized_workflow[:name], "Item closed"
    assert_equal serialized_workflow[:content_types], %w[Issue PullRequest]
  end

  def test_workflows_preserve_enabled_status
    disabled_workflow = create(:memex_project_workflow,
      name: "Disabled workflow",
      memex_project: @memex,
      content_types: ["PullRequest"],
      enabled: false,
      trigger_type: :review_approved,
    )
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_workflow = serialized_memex[:workflows].find { |w| w[:trigger_type] == "review_approved" }

    assert_equal serialized_workflow[:enabled], false
  end

  def test_workflows_replace_ids_with_strings
    workflow = create(:memex_project_workflow,
      name: "Workflow",
      memex_project: @memex,
      content_types: ["PullRequest"],
      enabled: true,
      trigger_type: :review_approved,
    )

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_workflow = serialized_memex[:workflows].find { |w| w[:trigger_type] == "review_approved" }
    serialized_action = serialized_workflow[:actions_attributes].first

    assert_nil serialized_action[:arguments][:fieldId]
    assert_nil serialized_action[:arguments][:fieldOptionId]

    assert_equal serialized_action[:action_type], "set_field"
    assert_equal serialized_action[:arguments][:fieldName], "status"
    assert_equal serialized_action[:arguments][:fieldOptionName], "📋 Backlog"
  end

  def test_workflows_excludes_auto_add
    repo = create(:repository)
    workflow = create(:memex_project_workflow,
      name: "Auto-add workflow",
      memex_project: @memex,
      content_types: %w[Issue PullRequest],
      enabled: true,
      trigger_type: :query_matched,
      actions: [
        create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:pr,issue is:open", "repositoryId" => repo.id }),
        create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => repo.id })
      ]
    )

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_workflow = serialized_memex[:workflows].find { |w| w[:trigger_type] == "query_matched" }

    assert_nil serialized_workflow
  end

  def test_insights_configuration_included
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_chart = serialized_memex[:insights].find { |w| w[:number] == 1 }

    assert_equal serialized_chart[:name], "Current iteration"
    assert_equal serialized_chart[:configuration].is_a?(Hash), true
    assert_equal serialized_chart[:configuration][:type], "line"
  end

  def test_insights_datasource_column_converted_to_string
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_chart = serialized_memex[:insights].find { |w| w[:number] == 1 }

    datasource = serialized_chart[:configuration][:xAxis][:dataSource]

    assert_equal datasource[:columnName], "status"
    assert_nil datasource[:column]
  end

  def test_insights_groupby_column_converted_to_string
    # Allow more than 2 charts for this test
    GitHub.flipper[:memex_charts_basic_allow].enable

    # Add a new chart with groupby configuration
    milestone_column = @memex.columns.find { |c| c.name == "Milestone" }
    @memex.charts.create!(
      creator: @admin,
      name: "group by chart",
      number: 3,
      configuration: {
        "time" => { "period" => "2W" },
        "type" => "stacked-column",
        "xAxis" => {
          "dataSource" => {
            "column" => @memex.columns.find(&:status?).id
          },
          "groupBy" => {
            "column" => milestone_column.id
          }
        },
        "yAxis" => { "aggregate" => { "operation" => "count" } },
        "filter" => ""
      }
    )

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_chart = serialized_memex[:insights].find { |w| w[:number] == 3 }

    groupby = serialized_chart[:configuration][:xAxis][:groupBy]

    assert_equal groupby[:columnName], "milestone"
    assert_nil groupby[:column]
  end

  def test_insights_aggregate_columns_converted_to_string
    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_chart = serialized_memex[:insights].find { |w| w[:number] == 2 }

    aggregate = serialized_chart[:configuration][:yAxis][:aggregate]

    assert_equal aggregate[:columnNames], ["estimate"]
    assert_nil aggregate[:columns]
  end

  test "converts aggregation settings to names" do
    column = create(:memex_project_column, name: "Staffing", data_type: :number, memex_project: @memex)
    estimate_column = @memex.columns.find { |c| c.name == "Estimate" }

    board_view = create(
      :memex_project_view,
      name: "Aggregation Settings",
      layout: "board_layout",
      memex_project: @memex,
      priority: 1,
      aggregation_settings: {
        hide_items_count: true,
        sum: [column.id, estimate_column.id, @memex.status_column.id]
      }
    )

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:name] == board_view.name }

    assert_equal({ hide_items_count: true, sum: %w[staffing estimate] }, serialized_view[:aggregation_settings_by_name])
  end

  test "does not crash when aggregation settings is nil" do
    column = create(:memex_project_column, name: "Staffing", data_type: :number, memex_project: @memex)
    estimate_column = @memex.columns.find { |c| c.name == "Estimate" }

    board_view = create(
      :memex_project_view,
      name: "Aggregation Settings",
      layout: "board_layout",
      memex_project: @memex,
      priority: 1,
      aggregation_settings: nil
    )
    board_view.update_attribute(:aggregation_settings, nil)

    serialized_memex = MemexProject::StructureSerializer.new(@memex).serialize
    serialized_view = serialized_memex[:views].find { |v| v[:name] == board_view.name }

    assert_equal({}, serialized_view[:aggregation_settings_by_name])
  end

  private def assert_column_limit(serialized_view:, column_slug:, option_id:, column_limit:)
    assert_equal column_limit, serialized_view[:layout_settings_by_name]["board"]["column_limits"][column_slug][option_id]
  end
end
