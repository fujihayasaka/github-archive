# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectMigrationStatusType < Platform::Enums::Base
      description "The status of a project migration."
      visibility :internal

      value "READY", "No migration has been created but the project can be migrated."
      value "PENDING", "The migration has been created but has not been started."
      value "IN_PROGRESS_PROJECT_DETAILS", "The project details have been migrated."
      value "IN_PROGRESS_STATUS_FIELDS", "The status field details have been migrated."
      value "IN_PROGRESS_DEFAULT_VIEW", "The default view details have been migrated."
      value "IN_PROGRESS_PERMISSIONS", "The permissions for the project have been migrated."
      value "IN_PROGRESS_ITEMS", "The items for the project have been migrated."
      value "IN_PROGRESS_WORKFLOWS", "The workflows for the project have been migrated."
      value "COMPLETED", "The migration has completed."
      value "ERROR", "The migration was not successful."
    end
  end
end
