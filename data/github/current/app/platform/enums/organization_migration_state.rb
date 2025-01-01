# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationMigrationState < Platform::Enums::Base
      description "The Octoshift Organization migration state."

      value "NOT_STARTED", "The Octoshift migration has not started.", value: :ORG_MIGRATION_STATE_NOT_STARTED
      value "QUEUED", "The Octoshift migration has been queued.", value: :ORG_MIGRATION_STATE_QUEUED
      value "IN_PROGRESS", "The Octoshift migration is in progress.", value: :ORG_MIGRATION_STATE_IN_PROGRESS
      value "PRE_REPO_MIGRATION", "The Octoshift migration is performing pre repository migrations.", value: :ORG_MIGRATION_STATE_PRE_REPO_MIGRATION
      value "REPO_MIGRATION", "The Octoshift org migration is performing repository migrations.", value: :ORG_MIGRATION_STATE_REPO_MIGRATION
      value "POST_REPO_MIGRATION", "The Octoshift migration is performing post repository migrations.", value: :ORG_MIGRATION_STATE_POST_REPO_MIGRATION
      value "SUCCEEDED", "The Octoshift migration has succeeded.", value: :ORG_MIGRATION_STATE_SUCCEEDED
      value "FAILED", "The Octoshift migration has failed.", value: :ORG_MIGRATION_STATE_FAILED
      value "PENDING_VALIDATION", "The Octoshift migration needs to have its credentials validated.", value: :ORG_MIGRATION_STATE_PENDING_VALIDATION
      value "FAILED_VALIDATION", "The Octoshift migration has invalid credentials.", value: :ORG_MIGRATION_STATE_FAILED_VALIDATION
    end
  end
end
