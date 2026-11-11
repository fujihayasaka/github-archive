# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2SingleSelectFieldOptionInput < Platform::Inputs::Base
      description "Represents a single select field option"
      visibility :public, environments: [:dotcom, :enterprise]

      argument :name, String, "The name of the option", required: true
      argument :color, Enums::ProjectV2SingleSelectFieldOptionColor, "The display color of the option", required: true
      argument :description, String, "The description text of the option", required: true
    end
  end
end
