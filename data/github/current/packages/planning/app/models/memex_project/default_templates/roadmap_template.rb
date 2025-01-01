# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  RoadmapTemplate = {
    id: "roadmap_template",
    title: "Roadmap",
    short_description: "Manage your team's long term plans as you plan out your roadmap",
    image_url: {
      light: "modules/memexes/memex-templates-roadmap-template-light.png",
      dark: "modules/memexes/memex-templates-roadmap-template-dark.png",
    },
    columns: [
      {
        name: "Status",
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
            { "id" => "9282166a", "name" => "Squad 1", "color" => "PINK", "description" => "", },
            { "id" => "8a5d08e5", "name" => "Squad 2", "color" => "ORANGE", "description" => "", },
            { "id" => "478d0b17", "name" => "Squad 3", "color" => "GREEN", "description" => "", }
          ]
        },
        visible: true
      },
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
      {
        name: "Quarter",
        data_type: :iteration,
        default_column: false,
        user_defined: true,
        settings: {
          "configuration" => {
            "duration" => 90,
            "start_day" => 1,
            "iterations" => [
              { "id" => "5f6bfd38", "title" => "Quarter 1", "duration" => 90, "start_date" => Date.today.to_s },
              { "id" => "b64ce631", "title" => "Quarter 2", "duration" => 90, "start_date" => (Date.today + 90.days).to_s  },
              { "id" => "a0844f8e", "title" => "Quarter 3", "duration" => 90, "start_date" => (Date.today + 180.days).to_s  }
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
        name: "Monthly roadmap",
        visible_fields_by_name: %w[title assignees status team sub-issues-progress iteration start-date end-date quarter],
        layout: :roadmap_layout,
        group_by_fields_by_name: ["team"],
        column_field_by_name: ["quarter"],
        layout_settings_by_name: { "roadmap" => { "zoom_level" => "month", "date_fields" => %w[start-date end-date], "column_widths" => { "55091989" => 350 } } }
      },
      {
        name: "Quarterly roadmap",
        visible_fields_by_name: %w[title assignees status],
        layout: :roadmap_layout,
        group_by_fields_by_name: ["team"],
        layout_settings_by_name: { "roadmap" => { "zoom_level" => "quarter", "date_fields" => %w[quarter quarter] } }
      },
      {
        name: "Backlog",
        visible_fields_by_name: %w[title assignees sub-issues-progress start-date end-date iteration quarter team],
        layout: :table_layout,
        group_by_fields_by_name: ["team"],
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
