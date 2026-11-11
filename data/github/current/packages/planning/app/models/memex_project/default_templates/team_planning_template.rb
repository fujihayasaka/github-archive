# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  module TeamPlanningTemplate
    # Image paths for template dialog
    IMAGE_PATHS = {
      light: "modules/memexes/memex-templates-team-planning-updated-light.png",
      dark: "modules/memexes/memex-templates-team-planning-updated-dark.png",
    }.freeze

    # Shared views used in the template
    SHARED_VIEWS = [
      {
        name: "Current iteration",
        visible_fields_by_name: %w[title assignees status linked-pull-requests sub-issues-progress],
        layout: :board_layout,
        filter: "iteration:@current",
        group_by_fields_by_name: ["priority"],
        aggregation_settings_by_name: {
          sum: ["estimate"],
          hide_items_count: false
        },
        layout_settings_by_name: {
          "board" => {
            "column_limits" => {
              "status" => {
                "47fc9ee4" => 5,
                "f75ad846" => 3
              }
            }
          }
        }
      },
      {
        name: "Roadmap",
        visible_fields_by_name: %w[title assignees status],
        layout: :roadmap_layout,
        layout_settings_by_name: {
          "roadmap" => {
            "date_fields" => %w[iteration iteration]
          }
        }
      },
      {
        name: "My items",
        visible_fields_by_name: %w[title priority linked-pull-requests sub-issues-progress size estimate iteration],
        layout: :table_layout,
        filter: "assignee:@me",
        slice_by_field_by_name: {
          field_name: "status"
        }
      }
    ].freeze

    VIEWS = [
      {
        name: "Backlog",
        visible_fields_by_name: %w[title assignees status linked-pull-requests sub-issues-progress iteration estimate start-date target-date],
        layout: :table_layout,
        group_by_fields_by_name: ["status"],
        aggregation_settings_by_name: {
          sum: ["estimate"],
          hide_items_count: false
        }
      },
      {
        name: "Board",
        visible_fields_by_name: %w[title assignees status linked-pull-requests sub-issues-progress priority estimate size iteration],
        layout: :board_layout,
        sort_by_fields_by_name: [%w[priority asc]],
        aggregation_settings_by_name: {
          sum: ["estimate"],
          hide_items_count: false
        },
        layout_settings_by_name: {
          "board" => {
            "column_limits" => {
              "status" => {
                "47fc9ee4" => 5,
                "f75ad846" => 5
              }
            }
          }
        }
      },
      *SHARED_VIEWS
    ].freeze

    TEMPLATE = {
    title: "Team planning",
    id: "team_planning",
    short_description: "Manage your team's work items, plan upcoming cycles, and understand team capacity",
    image_url: IMAGE_PATHS,
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: false,
        settings: {
          options: [
            { "id" => "f75ad846", "name" => "Todo", "color" => "GREEN", "description" => "This item hasn't been started" },
            { "id" => "47fc9ee4", "name" => "In progress", "color" => "YELLOW", "description" => "This is actively being worked on" },
            { "id" => "98236657", "name" => "Done", "color" => "PURPLE", "description" => "This has been completed" }
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
          "width" => 200,
          "options" => [
            { "name" => "P0", "color" => "RED", "description" => "" },
            { "name" => "P1", "color" => "ORANGE", "description" => "" },
            { "name" => "P2", "color" => "YELLOW", "description" => "" }
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
          "width" => 200,
          "options" => [
            { "name" => "XS", "color" => "GREEN", "description" => "" },
            { "name" => "S", "color" => "RED", "description" => "" },
            { "name" => "M", "color" => "BLUE", "description" => "" },
            { "name" => "L", "color" => "PURPLE", "description" => "" },
            { "name" => "XL", "color" => "YELLOW", "description" => "" }
          ]
        },
        visible: true
      },
      {
        name: "Estimate",
        data_type: :number,
        default_column: false,
        user_defined: true,
        settings: nil,
        visible: true
      },
      {
        name: "Iteration",
        data_type: :iteration,
        default_column: false,
        user_defined: true,
        settings: {
          configuration: {
            start_day: 1,
            duration: 14,
            iterations: [
              {
                title: "Iteration",
                start_date: Date.today.to_s,
                duration: 14
              },
              {
                title: "Iteration 2",
                start_date: (Date.today + 14.days).to_s,
                duration: 14
              },
              {
                title: "Iteration 3",
                start_date: (Date.today + 28.days).to_s,
                duration: 14
              }
            ]
          }
        },
        visible: true
      },
      {
        name: "Start date",
        data_type: :date,
        default_column: false,
        user_defined: true,
        settings: nil,
        visible: true
      },
      {
        name: "Target date",
        data_type: :date,
        default_column: false,
        user_defined: true,
        settings: nil,
        visible: true
      }
    ],
    views: VIEWS,
    workflows: Shared::Workflows.standard_workflows + [
      Shared::Workflows.item_added_to_project_workflow("Todo")
    ],
    insights: [
      {
        name: "Status chart",
        number: 1,
        configuration: {
          type: "column",
          xAxis: { dataSource: { columnName: "status" } },
          yAxis: { aggregate: { operation: "count" } },
          filter: ""
        }
      }
    ]
  }.freeze
  end
end
