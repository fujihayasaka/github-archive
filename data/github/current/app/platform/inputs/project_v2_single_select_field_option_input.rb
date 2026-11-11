# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2SingleSelectFieldOptionInput < Platform::Inputs::Base
      docs_category :projects
      description "Represents a single select field option"
      visibility :public, environments: [:dotcom, :enterprise]

      argument :id, String, "The ID of an existing single select option. Include this to preserve the option's identity during updates, preventing item field values from being cleared.", required: false
      argument :name, String, "The name of the option", required: true
      argument :color, Enums::ProjectV2SingleSelectFieldOptionColor, "The display color of the option", required: true
      argument :description, String, "The description text of the option", required: true
    end
  end
end
