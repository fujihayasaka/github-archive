# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFieldSingleSelectOptionInput < Platform::Inputs::Base
      description "A single selection option for an issue field."

      argument :name, String, "The name of the option.", required: true
      argument :color, Enums::IssueFieldSingleSelectOptionColor, "The color associated with the option.", required: false
      argument :description, String, "A description of the option.", required: false
      argument :priority, Int, "The priority of the option in the list.", required: false
    end
  end
end
