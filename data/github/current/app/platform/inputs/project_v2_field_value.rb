# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2FieldValue < Platform::Inputs::Base
      description "The values that can be used to update a field of an item inside a Project. Only 1 value can be updated at a time."

      argument :text, String, "The text to set on the field.", required: false
      argument :number, Float, "The number to set on the field.", required: false
      argument :date, Scalars::Date, "The ISO 8601 date to set on the field.", required: false
      argument :single_select_option_id, String, "The id of the single select option to set on the field.", required: false
      argument :iteration_id, String, "The id of the iteration to set on the field.", required: false

      validates required: { one_of: [:text, :number, :date, :single_select_option_id, :iteration_id] }
    end
  end
end
