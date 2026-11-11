# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AddOrCreateLabelsLabelInput < Platform::Inputs::Base
      graphql_name "AddOrCreateLabelsLabelInput"
      description "Specifies the attributes for a label to be added or created."
      visibility :under_development

      argument :color, String, "A 6 character hex code, without the leading #, identifying the color of the label.", required: false
      argument :description, String, "A brief description of the label, such as its purpose.", required: false
      argument :name, String, "The name of the label.", required: true
    end
  end
end
