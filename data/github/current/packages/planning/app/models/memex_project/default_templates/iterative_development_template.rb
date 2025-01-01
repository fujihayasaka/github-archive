# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  IterativeDevelopmentTemplate = {
    id: "iterative_development",
    title: "Iterative development",
    short_description: "Plan your current and upcoming iterations as you work through your prioritized backlog of items",
    image_url: {
      light: "modules/memexes/memex-templates-iterative-development-light.png",
      dark: "modules/memexes/memex-templates-iterative-development-dark.png",
    },
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: false,
        user_defined: false,
        settings: {
          "options" => [
            { "id" => "f75ad846", "name" => "Backlog", "color" => "GREEN", "description" => "This item hasn't been started" },
            { "id" => "e18bf179", "name" => "Ready", "color" => "BLUE", "description" => "This is ready to be picked up" },
            { "id" => "47fc9ee4", "name" => "In progress", "color" => "YELLOW", "description" => "This is actively being worked on" },
            { "id" => "aba860b9", "name" => "In review", "color" => "PURPLE", "description" => "This item is in review" },
            { "id" => "98236657", "name" => "Done", "color" => "ORANGE", "description" => "This has been completed" }
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
            { "id" => "79628723", "name" => "P0", "color" => "RED", "description" => "" },
            { "id" => "0a877460", "name" => "P1", "color" => "ORANGE", "description" => "" },
            { "id" => "da944a9c", "name" => "P2", "color" => "YELLOW", "description" => "" }
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
            { "id" => "911790be", "name" => "XS", "color" => "GREEN", "description" => "" },
            { "id" => "b277fb01", "name" => "S", "color" => "PURPLE", "description" => "" },
            { "id" => "86db8eb3", "name" => "M", "color" => "YELLOW", "description" => "" },
            { "id" => "853c8207", "name" => "L", "color" => "ORANGE", "description" => "" },
            { "id" => "2d0801e2", "name" => "XL", "color" => "RED", "description" => "" }
          ]
        },
        visible: true
      },
      { name: "Estimate", data_type: :number, default_column: false, user_defined: true, settings: nil, visible: true },
      {
        name: "Iteration",
        data_type: :iteration,
        default_column: false,
        user_defined: true,
        settings: {
          "configuration" => {
            "duration" => 14,
            "start_day" => 1,
            "iterations" => [
              { "id" => "955c1297", "title" => "Iteration 5", "duration" => 14, "start_date" => (Date.today + 56.days).to_s },
              { "id" => "b6a8f1bb", "title" => "Iteration 4", "duration" => 14, "start_date" => (Date.today + 42.days).to_s },
              { "id" => "d2c335bc", "title" => "Iteration 3", "duration" => 14, "start_date" => (Date.today + 28.days).to_s },
              { "id" => "54cf5c95", "title" => "Iteration 2", "duration" => 14, "start_date" => (Date.today + 14.days).to_s },
              { "id" => "381c7c80", "title" => "Iteration 1", "duration" => 14, "start_date" => Date.today.to_s }
            ],
          }
        },
        visible: true
      }
    ],
    views: [
      {
        name: "Current iteration",
        visible_fields_by_name: %w[title assignees status sub-issues-progress priority size estimate],
        layout: :board_layout,
        filter: "iteration:@current",
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 3, "aba860b9" => 5, "f75ad846" => 3 } } } }
      },
      {
        name: "Next iteration",
        visible_fields_by_name: %w[title assignees sub-issues-progress status],
        layout: :board_layout,
        filter: "iteration:@next",
        group_by_fields_by_name: ["priority"],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 3, "aba860b9" => 5, "f75ad846" => 3 } } } }
      },
      {
        name: "Prioritized backlog",
        visible_fields_by_name: %w[title assignees status sub-issues-progress priority estimate size iteration],
        layout: :board_layout,
        group_by_fields_by_name: ["priority"],
        sort_by_fields_by_name: [%w[priority asc]],
        slice_by_field_by_name: { filter: "", field_name: "assignees" },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 3, "aba860b9" => 5, "f75ad846" => 3 } } } }
      },
      {
        name: "Roadmap",
        visible_fields_by_name: %w[title assignees status size],
        layout: :roadmap_layout,
        layout_settings_by_name: { "roadmap" => { "date_fields" => %w[iteration iteration] } }
      },
      {
        name: "In review",
        visible_fields_by_name: %w[title assignees sub-issues-progress linked-pull-requests reviewers repository],
        layout: :table_layout,
        filter: "status:\"In review\"",
      },
      {
        name: "My items",
        visible_fields_by_name: %w[title priority sub-issues-progress size estimate iteration linked-pull-requests],
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
