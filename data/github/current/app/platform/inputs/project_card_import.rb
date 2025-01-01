# typed: true
# frozen_string_literal: true

class Platform::Inputs::ProjectCardImport < Platform::Inputs::Base
  description "An issue or PR and its owning repository to be used in a project card."

  argument :repository, String, "Repository name with owner (owner/repository).", required: true
  argument :number, Integer, "The issue or pull request number.", required: true
end
