# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SuggestedChange < Platform::Inputs::Base


      graphql_name "SuggestedChange"
      description "Describes a suggested change to a file to be applied in a new commit."
      visibility :under_development

      argument :comment_id, ID, "ID of the comment with the suggested change.", required: true
      argument :suggestion, [String], "The contents of the code suggestion, e.g. ['def new_method']", required: false
      argument :path, String, "The file path relative to the root of the repository.", required: true
    end
  end
end
