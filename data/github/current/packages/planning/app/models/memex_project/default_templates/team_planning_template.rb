# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  TeamPlanningTemplate = {
    title: "Team planning",
    id: "team_planning",
    short_description: "Manage your team's work items, plan upcoming cycles, and understand team capacity",
    image_url: {
      light: "modules/memexes/memex-templates-team-planning-light.png",
      dark: "modules/memexes/memex-templates-team-planning-dark.png",
    },
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: false,
        settings: {
          options: [
            { "id" => "f75ad846", "name" => "Todo", "color" => "GREEN", "description" => "This item hasn't been started" },
            { "id" => "47fc9ee4", "name" => "In Progress", "color" => "YELLOW", "description" => "This is actively being worked on" },
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
        name: "End date",
        data_type: :date,
        default_column: false,
        user_defined: true,
        settings: nil,
        visible: true
      }
    ],
    views: [
      {
        name: "Backlog",
        visible_fields_by_name: %w[title assignees status priority estimate size iteration],
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
      {
        name: "Team capacity",
        visible_fields_by_name: %w[title status size estimate iteration start-date end-date],
        layout: :table_layout,
        group_by_fields_by_name: ["priority"],
        aggregation_settings_by_name: {
          sum: ["estimate"],
          hide_items_count: false
        },
        slice_by_field_by_name: {
          field_name: "assignees"
        }
      },
      {
        name: "Current iteration",
        visible_fields_by_name: %w[title assignees status],
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
        visible_fields_by_name: %w[title priority size estimate iteration linked-pull-requests],
        layout: :table_layout,
        filter: "assignee:@me",
        slice_by_field_by_name: {
          field_name: "status"
        }
      }
    ],
    workflows: [
      {
        name: "Item closed",
        trigger_type: "closed",
        enabled: true,
        content_types: %w[Issue PullRequest],
        actions_attributes: [
          {
            action_type: "set_field",
            arguments: { fieldName: "status", fieldOptionName: "Done" }
          }
        ]
      },
      {
        name: "Pull request merged",
        trigger_type: "merged",
        enabled: true,
        content_types: ["PullRequest"],
        actions_attributes: [
          {
            action_type: "set_field",
            arguments: { fieldName: "status", fieldOptionName: "Done" }
          }
        ]
      },
      { name: "Auto-close issue", trigger_type: "project_item_column_update", enabled: true, content_types: ["Issue"], actions_attributes: [{ action_type: "get_project_items", arguments: { fieldName: "status", fieldOptionName: "Done" } }, { action_type: "close_item", arguments: {} }] }
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
