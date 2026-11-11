# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Helpers
        module LegacyMigrationHelper
          UUID_REGEX = /[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/

          private

          def find_legacy_migration(raw_id)
            return nil if raw_id.blank?

            if raw_id.match?(/\A\d+\z/)
              find_legacy_migration_by_id(raw_id.to_i)
            elsif raw_id.match?(UUID_REGEX) && raw_id.length == 36
              Migration.find_by(guid: raw_id)
            else
              migration_id = parse_global_relay_id(raw_id)
              find_legacy_migration_by_id(migration_id) if migration_id
            end
          end

          def find_legacy_migration_by_id(migration_id)
            Migration.find_by(id: migration_id)
          end

          def parse_global_relay_id(raw_id)
            Platform::Helpers::GlobalId.parse(raw_id).id
          rescue StandardError
            nil
          end

          def legacy_migration_not_found(migration_id)
            Twirp::Error.not_found(
              "LegacyMigration not found.",
              argument: "migration_id",
              value: migration_id
            )
          end

          def extend_archive_ttl_for!(migration, days)
            new_expiry = days.days.from_now.utc
            migration.file.update_columns(updated_at: new_expiry)
            new_expiry
          end

          def build_legacy_migration_hash(migration)
            {
              migration: {
                id: migration.id,
                guid: migration.guid,
                global_relay_id: migration.global_relay_id,
                state: migration.current_state.name,
                migratable_resources_count: migration.migratable_resources_count,
                migrated_resources_count: migration.migratable_resources.migrated.count,
                owner_login: migration.owner&.login,
                owner_id: migration.owner_id,
                creator_login: migration.creator&.login,
                creator_id: migration.creator_id,
                created_at: migration.created_at.utc,
                updated_at: migration.updated_at.utc,
                lock_repositories: migration.lock_repositories,
                exclude_attachments: migration.exclude_attachments,
                exclude_releases: migration.exclude_releases,
                exclude_owner_projects: migration.exclude_owner_projects,
                exclude_git_data: migration.exclude_git_data,
                exclude_metadata: migration.exclude_metadata,
                org_metadata_only: migration.org_metadata_only,
                file_exists: migration.file.present?,
                file_size: migration.file&.size || 0,
                is_gsm_migration: migration.respond_to?(:is_gsm_migration) ? migration.is_gsm_migration : false,
                import_migration_source: migration.respond_to?(:import_migration_source) ? migration.import_migration_source.to_s : "",
                archive_download_url: migration.file ? migration.file.download_url(actor: migration.owner) : "",
                migratable_resource_counts: build_migratable_resource_counts(migration)
              }
            }
          end

          def build_migratable_resource_counts(migration)
            migration.migratable_resources
              .group(:state, :model_type)
              .count
              .map do |(state, model_type), count|
                {
                  model_type: model_type.to_s,
                  state: state.to_s,
                  count: count
                }
              end
          end

          def build_failed_models(migration)
            migration.migratable_resources.failed.to_a.map do |mr|
              {
                model_type: mr.model_type.to_s,
                model_id: mr.model_id.to_s,
                source_url: mr.source_url.to_s,
                target_url: mr.target_url.to_s,
                state: mr.state.to_s,
                warning: mr.warning.to_s
              }
            end
          end
        end
      end
    end
  end
end
