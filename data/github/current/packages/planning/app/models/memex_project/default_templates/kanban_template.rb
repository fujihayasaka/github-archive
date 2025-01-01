# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  KanbanTemplate = {
    id: "kanban",
    title: "Kanban",
    short_description: "Visualize the status of your project and limit work in progress",
    image_url: {
      light: "modules/memexes/memex-templates-kanban-light.png",
      dark: "modules/memexes/memex-templates-kanban-dark.png",
    },
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: false,
        settings: {
          "options" => [
            { "id" => "f75ad846", "name" => "Backlog", "color" => "GREEN", "description" => "This item hasn't been started", },
            { "id" => "61e4505c", "name" => "Ready", "color" => "BLUE", "description" => "This is ready to be picked up", },
            { "id" => "47fc9ee4", "name" => "In progress", "color" => "YELLOW", "description" => "This is actively being worked on", },
            { "id" => "df73e18b", "name" => "In review", "color" => "PURPLE", "description" => "This item is in review", },
            { "id" => "98236657", "name" => "Done", "color" => "ORANGE", "description" => "This has been completed", }
          ]
        },
        visible: true
      },
      {
        name: "Priority",
        data_type: :single_select,
        default_column: false,
        user_defined: true,
        settings: {
          "options" => [
            { "id" => "79628723", "name" => "P0", "color" => "RED", "description" => "", },
            { "id" => "0a877460", "name" => "P1", "color" => "ORANGE", "description" => "", },
            { "id" => "da944a9c", "name" => "P2", "color" => "YELLOW", "description" => "", }
          ]
        },
        visible: true
      },
      {
        name: "Size",
        data_type: :single_select,
        default_column: false,
        user_defined: true,
        settings: {
          "options" => [
            { "id" => "6c6483d2", "name" => "XS", "color" => "GREEN", "description" => "", },
            { "id" => "f784b110", "name" => "S", "color" => "PURPLE", "description" => "", },
            { "id" => "7515a9f1", "name" => "M", "color" => "RED", "description" => "", },
            { "id" => "817d0097", "name" => "L", "color" => "YELLOW", "description" => "", },
            { "id" => "db339eb2", "name" => "XL", "color" => "PINK", "description" => "", }
          ]
        },
        visible: true },
      { name: "Estimate", data_type: :number, default_column: false, user_defined: true, settings: nil, visible: true },
      { name: "Start date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true },
      { name: "End date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true }
    ],
   views: [
      {
        name: "Backlog",
        visible_fields_by_name: %w[title assignees status sub-issues-progress priority estimate size],
        layout: :board_layout,
        sort_by_fields_by_name: [%w[priority asc]],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 3, "df73e18b" => 5, "f75ad846" => 5 } } } }
      },
      {
        name: "Priority board",
        visible_fields_by_name: %w[title assignees status sub-issues-progress size estimate],
        layout: :board_layout,
        group_by_fields_by_name: ["priority"],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 3, "df73e18b" => 5, "f75ad846" => 5 } } } }\
      },
      {
        name: "Team items",
        visible_fields_by_name: %w[title status sub-issues-progress size estimate priority start-date end-date],
        layout: :table_layout,
        group_by_fields_by_name: ["status"],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        slice_by_field_by_name: { filter: "", field_name: "assignees" },
      },
      {
        name: "Roadmap",
        visible_fields_by_name: %w[title assignees status],
        layout: :roadmap_layout,
        layout_settings_by_name: { "roadmap" => { "date_fields" => %w[start-date end-date] } }
      },
      {
        name: "In review",
        visible_fields_by_name: %w[title assignees sub-issues-progress linked-pull-requests reviewers repository],
        layout: :table_layout,
        filter: "status:\"In review\"",
      },
      {
        name: "My items",
        visible_fields_by_name: %w[title priority sub-issues-progress size estimate linked-pull-requests],
        layout: :table_layout,
        filter: "assignee:@me",
        slice_by_field_by_name: { filter: "", field_name: "status" },
      }
    ],
    workflows: [
      { name: "Item closed", trigger_type: "closed", enabled: true, content_types: %w[Issue PullRequest], actions_attributes: [{ action_type: "set_field", arguments: { fieldName: "status", fieldOptionName: "Done" } }] },
      { name: "Pull request merged", trigger_type: "merged", enabled: true, content_types: ["PullRequest"], actions_attributes: [{ action_type: "set_field", arguments: { fieldName: "status", fieldOptionName: "Done" } }] },
      { name: "Auto-close issue", trigger_type: "project_item_column_update", enabled: true, content_types: ["Issue"], actions_attributes: [{ action_type: "get_project_items", arguments: { fieldName: "status", fieldOptionName: "Done" } }, { action_type: "close_item", arguments: {} }] },
      { name: "Auto-add sub-issues to project", trigger_type: "sub_issues", enabled: true, content_types: ["Issue"], actions_attributes: [{ action_type: "get_sub_issues", arguments: {} }, { action_type: "add_project_item", arguments: { subIssue: true } }] },
    ],
    insights: [{ name: "Status chart", number: 1, configuration: { type: "column", xAxis: { dataSource: { columnName: "status" } }, yAxis: { aggregate: { operation: "count" } }, filter: "" } }]
  }.freeze
end
