# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFilters < Platform::Inputs::Base
      docs_category :issues
      description "Ways in which to filter lists of issues."

      class IssueFieldValueFilter < Platform::Inputs::Base
        description "A filter for matching an issue field value. Exactly one value argument should be provided."

        argument :field_id, ID, "The ID of the issue field to filter by. Exactly one of `fieldId` or `fieldName` must be provided.", required: false
        argument :field_name, String, "The name of the issue field to filter by. Exactly one of `fieldId` or `fieldName` must be provided.", required: false
        argument :text_value, String, "Matches a text issue field value.", required: false
        argument :date_value, String, "Matches a date issue field value (YYYY-MM-DD).", required: false
        argument :number_value, Float, "Matches a numeric issue field value.", required: false
        argument :single_select_option_id, ID, "Matches a single-select issue field option by ID.", required: false
        argument :single_select_option_value, String, "Matches a single-select issue field option by name.", required: false
        argument :multi_select_option_ids, [ID], "Matches issues containing all of the multi-select issue field option IDs.", required: false
        argument :multi_select_option_values, [String], "Matches issues containing all of the multi-select issue field option names.", required: false
      end

      argument :assignee, String, "List issues assigned to given name. Pass in `null` for issues with no assigned user, and `*` for issues assigned to any user.", required: false
      argument :created_by, String, "List issues created by given name.", required: false
      argument :labels, [String], "List issues where the list of label names exist on the issue.", required: false
      argument :mentioned, String, "List issues where the given name is mentioned in the issue.", required: false
      argument :milestone, String, "List issues by given milestone argument. If an string representation of an integer is passed, it should refer to a milestone by its database ID. Pass in `null` for issues with no milestone, and `*` for issues that are assigned to any milestone.", required: false
      argument :milestone_number, String, "List issues by given milestone argument. If an string representation of an integer is passed, it should refer to a milestone by its number field. Pass in `null` for issues with no milestone, and `*` for issues that are assigned to any milestone.", required: false
      argument :since, Scalars::DateTime, "List issues that have been updated at or after the given date.", required: false
      argument :states,  [Enums::IssueState], "List issues filtered by the list of states given.", required: false
      argument :type,  String, "List issues filtered by the type given, only supported by searches on repositories.", required: false
      argument :issue_field_values, [IssueFieldValueFilter], "List issues where each supplied issue field value filter matches.", required: false, feature_flag: :issue_fields
      argument :viewer_subscribed, Boolean, "List issues subscribed to by viewer.", default_value: false, required: false
    end
  end
end
