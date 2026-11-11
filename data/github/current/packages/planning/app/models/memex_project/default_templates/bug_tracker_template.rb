# typed: true
# frozen_string_literal: true

require_relative "shared/workflows"

module MemexProject::DefaultTemplates
  BugTrackerTemplate = {
    title: "Bug tracker",
    id: "bug_tracker",
    short_description: "Track and triage your bugs 🐛",
    image_url: {
      light: "modules/memexes/memex-templates-bug-tracker-light.png",
      dark: "modules/memexes/memex-templates-bug-tracker-dark.png",
    },
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: false,
        settings: {
          "options" => [
            { "id" => "f971fb55", "name" => "To triage", "color" => "RED", "description" => "This needs to be triaged", },
            { "id" => "f75ad846", "name" => "Backlog", "color" => "GREEN", "description" => "This item hasn't been started", },
            { "id" => "856cdede", "name" => "Ready", "color" => "BLUE", "description" => "This is ready to be picked up", },
            { "id" => "47fc9ee4", "name" => "In progress", "color" => "YELLOW", "description" => "This is actively being worked on", },
            { "id" => "5ef0dc97", "name" => "In review", "color" => "PURPLE", "description" => "This item is in review", },
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
            { "id" => "3fd50a4c", "name" => "XS", "color" => "GREEN", "description" => "", },
            { "id" => "203d27bd", "name" => "S", "color" => "BLUE", "description" => "", },
            { "id" => "3da4ca48", "name" => "M", "color" => "PINK", "description" => "", },
            { "id" => "8d0cdae9", "name" => "L", "color" => "YELLOW", "description" => "", },
            { "id" => "71251445", "name" => "XL", "color" => "RED", "description" => "", }
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
              { "id" => "d2c335bc", "title" => "Iteration 3", "duration" => 14, "start_date" => (Date.today + 28.days).to_s, },
              { "id" => "54cf5c95", "title" => "Iteration 2", "duration" => 14, "start_date" => (Date.today + 14.days).to_s, },
              { "id" => "381c7c80", "title" => "Iteration 1", "duration" => 14, "start_date" => Date.today.to_s, }
            ],
          }
        },
        visible: true
      },
      { name: "Start date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true },
      { name: "Target date", data_type: :date, default_column: false, user_defined: true, settings: nil, visible: true }
    ],
    views: [
      {
        name: "Prioritized bugs",
        visible_fields_by_name: %w[title assignees linked-pull-requests sub-issues-progress size estimate iteration],
        layout: :board_layout,
        filter: "",
        aggregation_settings_by_name: { hide_items_count: false, sum: ["estimate"] },
        slice_by_field_by_name: { filter: "", field_name: "priority" },
        layout_settings_by_name: {
          "roadmap" => {
            "date_fields" => %w[iteration iteration],
            "column_widths" => { "55092264" => 350 }
          }
        }
      },
      {
        name: "Triage",
        visible_fields_by_name: %w[title priority linked-pull-requests sub-issues-progress size estimate assignees iteration],
        layout: :table_layout,
        filter: "status:\"To triage\"",
      },
      {
        name: "In review",
        visible_fields_by_name: %w[title assignees linked-pull-requests sub-issues-progress reviewers repository],
        layout: :table_layout,
        filter: "status:\"In review\"",
      },
      {
        name: "My items",
        visible_fields_by_name: %w[title priority linked-pull-requests sub-issues-progress size estimate iteration],
        layout: :table_layout,
        filter: "assignee:@me",
        group_by_fields_by_name: ["status"],
        slice_by_field_by_name: { filter: "", field_name: "status" },
      }
    ],
    workflows: Shared::Workflows.standard_workflows + [
      Shared::Workflows.item_added_to_project_workflow("To triage"),
      Shared::Workflows.workflow(:item_reopened_to_backlog)
    ],
    insights: [
      { name: "Status chart", number: 1, configuration: { type: "column", xAxis: { dataSource: { columnName: "status" } }, yAxis: { aggregate: { operation: "count" } }, filter: "" } }
    ]
  }.freeze
end
