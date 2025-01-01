# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::LockRepositoryAPIService.
      class LockRepositoryAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::LockRepositoryAPIService
        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        connected_to_writing_for :lock_repository, :unlock_repository

        def lock_repository(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s)
          end

          unless FeatureFlag.vexi.enabled?(:octoshift_prevent_start_of_migration_locking, repository, default: false)
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
            begin
              # Refresh Actions Workflow UI
              repository.refresh_workflows if !repository.feature_flag_enabled?(:octoshift_install_actions_app, default: false)

              repository.network.schedule_maintenance
            rescue NoMethodError, GitRPC::ObjectMissing => error_
              error_message = "Refresh Actions Workflow UI failed"
              error_details = error_.message
              error_payload = {
                "code.function" => "unlock_repository",
                "gh.repo.id" => req.repository_id,
                "exception.message" => error_details,
                "code.namespace" => "lock_repository_api_handler"
              }

              GitHub.logger.error(error_message, error_payload)
              # Still succeed with unlocking the repository as refresh_workflows is not always reliable and not required
            end
          end

          if FeatureFlag.vexi.enabled?(:octoshift_experimental_incremental_migrations, repository.owner, default: false)
            state = OctoshiftBatchHelper::TargetRepoState.fetch(repository.full_name)
            next_cursor = OctoshiftBatchHelper::MigrationState.fetch(state.current_octoshift_migration_id).next_cursor
            state.set_current_cursor(next_cursor)
          end

          # As part of octoshift_experimental_incremental_migrations, keep the
          # repo in an importing state until the full migration is complete
          # to prevent any unnecessary side effects.
          unless FeatureFlag.vexi.enabled?(:octoshift_prevent_end_of_migration_unlocking, repository.owner, default: false) || FeatureFlag.vexi.enabled?(:octoshift_prevent_end_of_migration_unlocking, repository, default: false)
            # Delete wiki if empty
            remove_empty_wiki!(repository)

            # Mark repository importing finished.
            ImportExport.domain.importing_stopped!(repository)

            repository.unlock!
          end

          # Kick off a batched-friendly MaintainTrackingRef for every Pull Request in the repository.
          PullRequests::BulkMaintainTrackingRefJob.perform_later(repository.id, importing: true)

          if should_enqueue_secret_scanning_backfill?(repository)
            # During the repo creation process (via Repository#create), the repository
            # may get secret scanning enabled if the owner or business has it set to be
            # auto-enabled.
            repository.ensure_backfill_scan_status
            repository.ensure_backfill_scan_if_enabled(actor: repository.import.creator)
          end

          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        def remove_empty_wiki!(repository)
          ActiveRecord::Base.connected_to(role: :writing) do
            orchestration = RepositoryOrchestration.purge_wiki(repository, skip_if_not_empty: true)

            if orchestration.valid?
              orchestration.execute!
            end
          end
        end

        private

        def should_enqueue_secret_scanning_backfill?(repo)
          SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        end
      end
    end
  end
end
