# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::LockRepositoryAPIService.
      class LockRepositoryAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::LockRepositoryAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]
        connected_to_writing_for :lock_repository, :unlock_repository

        def lock_repository(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s)
          end

          unless GitHub.flipper[:octoshift_prevent_start_of_migration_locking].enabled?(repository)
            repository.lock_for_migration
          end

          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        def unlock_repository(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s)
          end

          # Sync base permission based on Org default
          org = repository.owner
          repository.add_organization(org, action: org.default_repository_permission) unless !org.respond_to?(:default_repository_permission) || org.default_repository_permission == :none

          # clear max object size if it was set prior during import
          repository.clear_max_object_size(repository.user)

          ActiveRecord::Base.connected_to(role: :writing) do
            # Refresh Actions Workflow UI
            repository.refresh_workflows

            repository.network.schedule_maintenance
          end

          if GitHub.flipper[:octoshift_experimental_incremental_migrations].enabled?(repository.owner)
            state = OctoshiftBatchHelper::TargetRepoState.fetch(repository.full_name)
            next_cursor = OctoshiftBatchHelper::MigrationState.fetch(state.current_octoshift_migration_id).next_cursor
            state.set_current_cursor(next_cursor)
          end

          # As part of octoshift_experimental_incremental_migrations, keep the
          # repo in an importing state until the full migration is complete
          # to prevent any unnecessary side effects.
          unless GitHub.flipper[:octoshift_prevent_end_of_migration_unlocking].enabled?(repository.owner) || GitHub.flipper[:octoshift_prevent_end_of_migration_unlocking].enabled?(repository)
            # Mark repository importing finished.
            repository.importing_stopped!
            repository.unlock!
          end

          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
