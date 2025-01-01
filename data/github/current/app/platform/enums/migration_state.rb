# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MigrationState < Platform::Enums::Base
      description "The GitHub Enterprise Importer (GEI) migration state."

      value "NOT_STARTED", "The migration has not started.", value: :MIGRATION_STATE_NOT_STARTED
      value "QUEUED", "The migration has been queued.", value: :MIGRATION_STATE_QUEUED
      value "IN_PROGRESS", "The migration is in progress.", value: :MIGRATION_STATE_IN_PROGRESS
      value "SUCCEEDED", "The migration has succeeded.", value: :MIGRATION_STATE_SUCCEEDED
      value "FAILED", "The migration has failed.", value: :MIGRATION_STATE_FAILED
      value "PENDING_VALIDATION", "The migration needs to have its credentials validated.", value: :MIGRATION_STATE_PENDING_VALIDATION
      value "FAILED_VALIDATION", "The migration has invalid credentials.", value: :MIGRATION_STATE_FAILED_VALIDATION
    end
  end
end
