# typed: true
# frozen_string_literal: true

module MemexProject::DefaultTemplates
  TeamRetrospectiveTemplate = {
    id: "team_retrospective",
    title: "Team retrospective",
    short_description: "Reflect as a team what went well, what can be improved next time, and action items",
    image_url: {
      light: "modules/memexes/memex-templates-team-retrospective-light.png",
      dark: "modules/memexes/memex-templates-team-retrospective-dark.png",
    },
    columns: [
      {
        name: "Status",
        data_type: :single_select,
        default_column: false,
        user_defined: false,
        settings: {
          "options" => [
            { "id" => "f75ad846", "name" => "Agenda ✍", "color" => "PURPLE", "description" => "Agenda items for the retrospective", },
            { "id" => "47fc9ee4", "name" => "What went well 🟢", "color" => "GREEN", "description" => "What did we do well?", },
            { "id" => "98236657", "name" => "What can be improved 🟡", "color" => "YELLOW", "description" => "Where can we improve?", },
            { "id" => "ce9d32d6", "name" => "Action items ✍", "color" => "PINK", "description" => "Action items so we can improve moving forward", }
          ]
        },
        visible: true
      },
      {
        name: "Category",
        data_type: :single_select,
        default_column: false,
        user_defined: true,
        settings: {
          "options" => [
            { "id" => "6b33283e", "name" => "Team dynamics", "color" => "PINK", "description" => "", },
            { "id" => "4ddbe726", "name" => "Code reviews", "color" => "GREEN", "description" => "", },
            { "id" => "bdf03559", "name" => "Project planning", "color" => "BLUE", "description" => "", },
            { "id" => "e2c9ccc6", "name" => "Retrospective items", "color" => "YELLOW", "description" => "", }
          ]
        },
        visible: true
      },
      { name: "Notes", data_type: :text, default_column: false, user_defined: true, settings: nil, visible: true }
    ],
    views: [
      {
        name: "Retrospective",
        visible_fields_by_name: %w[title assignees status notes category],
        layout: :board_layout,
        aggregation_settings_by_name: { hide_items_count: false, sum: [] },
      },
      {
        name: "Categorize feedback",
        visible_fields_by_name: %w[title status category notes],
        layout: :table_layout,
        filter: "status:\"What went well 🟢\",\"What can be improved 🟡\"",
        group_by_fields_by_name: ["category"],
      },
      {
        name: "Action items",
        visible_fields_by_name: %w[title assignees category notes],
        layout: :table_layout,
        filter: "status:\"Action items ✍\"",
      }
    ],
    workflows: [
      { name: "Item closed", trigger_type: "closed", enabled: false, content_types: %w[Issue PullRequest], actions_attributes: [{ action_type: "set_field", arguments: { fieldName: "status", fieldOptionName: "What can be improved 🟡" } }] },
      { name: "Pull request merged", trigger_type: "merged", enabled: false, content_types: ["PullRequest"], actions_attributes: [{ action_type: "set_field", arguments: { fieldName: "status", fieldOptionName: "What can be improved 🟡" } }] }
    ],
    insights: [{ name: "Status chart", number: 1, configuration: { type: "column", xAxis: { dataSource: { columnName: "status" } }, yAxis: { aggregate: { operation: "count" } }, filter: "" } }]
  }.freeze
end
