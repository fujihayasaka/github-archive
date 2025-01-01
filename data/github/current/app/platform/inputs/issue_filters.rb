# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of issues."

      argument :assignee, String, "List issues assigned to given name. Pass in `null` for issues with no assigned user, and `*` for issues assigned to any user.", required: false
      argument :created_by, String, "List issues created by given name.", required: false
      argument :labels, [String], "List issues where the list of label names exist on the issue.", required: false
      argument :mentioned, String, "List issues where the given name is mentioned in the issue.", required: false
      argument :milestone, String, "List issues by given milestone argument. If an string representation of an integer is passed, it should refer to a milestone by its database ID. Pass in `null` for issues with no milestone, and `*` for issues that are assigned to any milestone.", required: false
      argument :milestone_number, String, "List issues by given milestone argument. If an string representation of an integer is passed, it should refer to a milestone by its number field. Pass in `null` for issues with no milestone, and `*` for issues that are assigned to any milestone.", required: false
      argument :since, Scalars::DateTime, "List issues that have been updated at or after the given date.", required: false
      argument :states,  [Enums::IssueState], "List issues filtered by the list of states given.", required: false
      argument :type,  String, "List issues filtered by the type given, only supported by searches on repositories.", required: false
      argument :viewer_subscribed, Boolean, "List issues subscribed to by viewer.", default_value: false, required: false
    end
  end
end
