# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2PermissionLevel < Platform::Enums::Base
      description "The possible roles of a collaborator on a project."

      value "READ", "The collaborator can view the project", value: "read"
      value "WRITE", "The collaborator can view and edit the project", value: "write"
      value "ADMIN", "The collaborator can view, edit, and maange the settings of the project", value: "admin"
    end
  end
end
