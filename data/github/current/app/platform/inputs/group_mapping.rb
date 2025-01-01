# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class GroupMapping < Platform::Inputs::Base
      graphql_name "GroupMapping"
      description "An external group mapping."
      visibility :under_development

      argument :group_id, ID, "ID of the external Group to map the Team to.", required: true
      argument :group_name, String, "The name for the external Group.", required: false
      argument :group_description, String, "The description for the external Group.", required: false
    end
  end
end
