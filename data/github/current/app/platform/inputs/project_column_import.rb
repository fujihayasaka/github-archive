# typed: true
# frozen_string_literal: true

class Platform::Inputs::ProjectColumnImport < Platform::Inputs::Base
  description "A project column and a list of its issues and PRs."

  argument :column_name, String, "The name of the column.", required: true
  argument :position, Integer, "The position of the column, starting from 0.", required: true
  argument :issues, [Platform::Inputs::ProjectCardImport], "A list of issues and pull requests in the column.", required: false
end
