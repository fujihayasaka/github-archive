# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2Roles < Platform::Enums::Base

      description "The possible roles of a collaborator on a project."

      value "NONE", "The collaborator has no direct access to the project", value: nil
      value "READER", "The collaborator can view the project", value: "project_reader"
      value "WRITER", "The collaborator can view and edit the project", value: "project_writer"
      value "ADMIN", "The collaborator can view, edit, and maange the settings of the project", value: "project_admin"
    end
  end
end
