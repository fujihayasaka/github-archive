# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  ProductLaunchTemplate = {
    id: "product_launch",
    title: "Product launch",
    short_description: "Manage work items across teams and functions when planning for a product launch 🚀",
    image_url: {
      light: "modules/memexes/memex-templates-product-launch-light.png",
      dark: "modules/memexes/memex-templates-product-launch-dark.png",
    },
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: false,
        settings: {
          "options" => [
            { "id" => "f75ad846", "name" => "Todo", "color" => "GREEN", "description" => "This item hasn't been started", },
            { "id" => "47fc9ee4", "name" => "In progress", "color" => "YELLOW", "description" => "This is actively being worked on", },
            { "id" => "98236657", "name" => "Done", "color" => "PURPLE", "description" => "This has been completed", }
          ]
        },
        visible: true
      },
      {
        name: "Team",
        data_type: :single_select,
        default_column: false,
        user_defined: true,
        settings: {
          "options" => [
            { "id" => "9282166a", "name" => "Engineering", "color" => "PINK", "description" => "", },
            { "id" => "8a5d08e5", "name" => "Product", "color" => "ORANGE", "description" => "", },
            { "id" => "478d0b17", "name" => "Design", "color" => "GREEN", "description" => "", },
            { "id" => "e6116d92", "name" => "Marketing", "color" => "BLUE", "description" => "", }
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
            { "id" => "5b58a44e", "name" => "XS", "color" => "GREEN", "description" => "", },
            { "id" => "d27407db", "name" => "S", "color" => "BLUE", "description" => "", },
            { "id" => "be2acfc7", "name" => "M", "color" => "PURPLE", "description" => "", },
            { "id" => "f265f403", "name" => "L", "color" => "ORANGE", "description" => "", },
            { "id" => "6cfde812", "name" => "XL", "color" => "RED", "description" => "", }
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
              { "id" => "d2c335bc", "title" => "Iteration 3", "duration" => 14, "start_date" => (Date.today + 28.days).to_s },
              { "id" => "54cf5c95", "title" => "Iteration 2", "duration" => 14, "start_date" => (Date.today + 14.days).to_s },
              { "id" => "381c7c80", "title" => "Iteration 1", "duration" => 14, "start_date" => Date.today.to_s }
            ],
          }
        },
        visible: true
      },
      { name: "Start date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true },
      { name: "End date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true }
    ],
    views: [
      {
        name: "Prioritized backlog",
        visible_fields_by_name: %w[title status assignees team sub-issues-progress size estimate linked-pull-requests iteration start-date end-date],
        layout: :table_layout,
        group_by_fields_by_name: ["priority"],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
      },
      {
        name: "Status board",
        visible_fields_by_name: %w[title assignees status sub-issues-progress priority estimate start-date end-date iteration size linked-pull-requests],
        layout: :board_layout,
        sort_by_fields_by_name: [%w[priority asc]],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        slice_by_field_by_name: { filter: "", field_name: "team" },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 5 } } } }
      },
      {
        name: "Current iteration",
        visible_fields_by_name: %w[title assignees status sub-issues-progress],
        layout: :board_layout,
        filter: "iteration:@current",
        group_by_fields_by_name: ["team"],
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        layout_settings_by_name: { "board" => { "column_limits" => { "status" => { "47fc9ee4" => 5 } } } }
      },
      {
        name: "Roadmap",
        visible_fields_by_name: %w[title assignees status],
        layout: :roadmap_layout,
        group_by_fields_by_name: ["team"],
        layout_settings_by_name: { "roadmap" => { "date_fields" => %w[iteration iteration] } }
      },
      {
        name: "Bugs 🐛 ",
        visible_fields_by_name: %w[title assignees status sub-issues-progress size estimate linked-pull-requests],
        layout: :table_layout,
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
