# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class VersionMigrationStatusProcessor < BaseProcessor
        default_to_write_connection!

        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "package_version_migration_status_processor"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.VersionMigrationStatus\Z/

        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        def process_message(original_message)
          return if (msg = VersionMigrationStatusMessage.new(original_message)).skipped?
          GitHub.logger.info(
            "Starting to process message",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_id" => msg.package.id,
            "gh.registry.package_name" => msg.package.name,
            "gh.registry.org_name" => msg&.package&.owner&.name,
            "gh.registry.repo_name" => msg.repo.name,
            "gh.registry.version_name" => msg.version.version,
          )

          #Here we are checking if the version has been updated since it was marked for migration
          #One of the scenario is when SHA is updated for the version during migration
          #in that case the update_date will be updated and we can easily remigrate the package with new data
          if GitHub.enterprise? && msg.should_remigrate_version == true
            msg.instance_variable_set(:@migration_state, "unmigrated")
            update_version_migration_state(msg)
            ::Packages::Migration::MigratePackageJob.perform_later(msg.package.id, force: msg.is_forced)
            GitHub.logger.info(
              "Enqueued re-migrate data-sync sha-update pending version",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
              "gh.registry.package_id" => msg.package.id,
              "gh.registry.version_id" => msg.version.id,
            )
            return
          end

          # migrated_package_id is set to 0 by CR Migrator for error cases
          if msg.package_type == "docker" && msg.migrated_package_id == 0
            GitHub.logger.info(
              "Skipping migration for package with error",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
            )
            update_version_migration_state(msg) if GitHub.enterprise? # update the migration state as error
            update_migration_run_status_for_enterprise(msg)
            update_migration_flag_or_state_if_migrated(msg)
            return
          end

          update_version_migration_state(msg)

          if msg.package&.migrated?
            if !GitHub.enterprise? || GitHub.actions_enabled?
              enable_actions_access_if_migrated(msg)
            end
            GitHub.logger.info(
              "Exchanging package from indexes",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
              "gh.registry.package_id" => msg.package.id,
              "gh.registry.migrated_package_id" => msg.migrated_package_id,
            )
            RemoveFromSearchIndexJob.perform_later("registry_package", msg.package.id, msg.repo.id)
            GlobalInstrumenter.instrument("package_registry.package_migration_complete", { package_id: msg.migrated_package_id })
          end

          sync_package_permissions_if_repo_migrated(msg)
          update_migration_run_status_for_enterprise(msg)
          remove_duplicate_action_access_entry(msg) if msg.package&.migrated?
          update_migration_flag_or_state_if_migrated(msg)
          enqueue_reset_docker_billing_job_if_migrated(msg) if msg.package_type == "docker"
          enqueue_migration_if_new_push_detected(msg)
        end

        # This function removes the duplicate action access entry for migrated packages if it exists. Shared lock makes it thread safe.
        def remove_duplicate_action_access_entry(msg)
          integration = Apps::Privileged.integration(:actions)
          count = IntegrationAllowedPackage.where(
            repository_id: msg.repo.id,
            package_id: msg.migrated_package_id,
            integration_id: integration.id
          ).count

          return if count <= 1
          GitHub.logger.info(
            "Removing 1 or more entries from IntegrationAllowedPackage table",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_count" => count,
            "gh.registry.repository_id" => msg.repo.id,
            "gh.registry.package_id" => msg.migrated_package_id,
          )

          IntegrationAllowedPackage.transaction do
            integration_allowed_packages = IntegrationAllowedPackage.lock("LOCK IN SHARE MODE").where(
              repository_id: msg.repo.id,
              package_id: msg.migrated_package_id,
              integration_id: integration.id
            )
            latest_integration_allowed = IntegrationAllowedPackage.new(repository_id: msg.repo.id, package_id: msg.migrated_package_id, access_type: :maintainer, integration_id: integration.id)

            if integration_allowed_packages.count > 1
              IntegrationAllowedPackage.where(
                repository_id: msg.repo.id,
                package_id: msg.migrated_package_id,
                integration_id: integration.id
              ).delete_all
              latest_integration_allowed.save!
            end
          end
        end

        def update_version_migration_state(msg)
          is_completed = msg.migration_state == "complete" && !msg.version.migrated? && !msg.version.deleted?
          msg.version.migration_state = msg.migration_state
          size_in_bytes = ActiveRecord::Base.connected_to(role: :reading) { msg.version.files.pluck(:size).sum }
          pkg_visibility = msg.package.visibility

          ::Registry::Package.throttle_writes_with_retry(max_retry_count: 5) do
            ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry do
              ::Registry::Package.transaction do
                ::Billing::SharedStorage::ArtifactEvent.transaction do
                  msg.version.save!(touch: false)

                  # Billing in v1 is at repo level, billing in v2 is at org level
                  # so, transfer billing events from repo to org

                  if is_completed && !msg.is_docker?
                    events = [
                      {
                        owner_id: msg.package.owner_id,
                        repository_id: msg.package.repository_id,
                        effective_at: Time.current,
                        source: :gpr,
                        repository_visibility: pkg_visibility,
                        event_type: :remove,
                        size_in_bytes: size_in_bytes,
                      },
                    ]

                    # For public packages we need to remove from v1 but not add it in v2 as in v1 we have artifact-events for public packages too.
                    events << {
                      owner_id: msg.package.owner_id,
                      repository_id: nil,
                      effective_at: Time.current,
                      source: :packages_v2,
                      repository_visibility: :private,
                      event_type: :add,
                      size_in_bytes: size_in_bytes,
                    } if pkg_visibility != "public"

                    ::Billing::SharedStorage::ArtifactEvent.create!(events)
                  end
                end
              end
            end
          end
        end

        # Only enables actions access if the package has been fully migrated
        def enable_actions_access_if_migrated(msg)
          integration = Apps::Privileged.integration(:actions)

          count = IntegrationAllowedPackage.where(
            repository_id: msg.repo.id,
            package_id: msg.migrated_package_id,
            integration_id: integration.id
          ).count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.migrated_package_id" => msg.migrated_package_id,
            "gh.registry.repository_id" => msg.repo.id,
            "gh.registry.integration_id" => integration.id,
            "gh.registry.count" => count,
          )

          # Don't add the same repo multiple times
          return if count > 0

          IntegrationAllowedPackage.throttle_writes_with_retry(max_retry_count: 5) do
            IntegrationAllowedPackage.new(
              repository_id: msg.repo.id,
              package_id: msg.migrated_package_id,
              access_type: :maintainer,
              integration_id: integration.id
            ).save
          end
        end

        # Only enqueues the SyncPackagePermsOnRepoChangeJob if all packages in a repo have been migrated
        def sync_package_permissions_if_repo_migrated(msg)
          return if msg&.repo&.nil?

          unmigrated_count = Registry::PackageVersion.joins(:package)
            .where(
              package: {
                repository_id: msg.repo.id,
                package_type: msg.package_type
              }
            )
            .unmigrated
            .count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_type" => msg.package_type,
            "gh.registry.repository_id" => msg.repo.id,
            "gh.registry.unmigrated_count" => unmigrated_count,
          )

          if unmigrated_count == 0
            Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: msg.repo)
          end
        end

        # Update the migration run status for enterprise environments only
        # If all the package versions has been migrated, increment the successfully package migrated count
        # If any of the package version migration resulted in error/retriable_error, increment the failed package migrated count
        def update_migration_run_status_for_enterprise(msg)
          return if !GitHub.enterprise?

          # unmigrated + pending + retriable_error
          unmigrated_count = Registry::PackageVersion.joins(:package)
            .where(
              package: {
                id: msg.package.id,
                package_type: msg.package_type
              }
            )
            .unmigrated
            .count

          # retriable_error
          failed_count = Registry::PackageVersion.joins(:package)
            .where(
              package: {
                id: msg.package.id,
                package_type: msg.package_type
              }
            )
            .migratable(msg.package_type, error_only: true)
            .count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_id" => msg.package.id,
            "gh.registry.package_type" => msg.package_type,
            "gh.registry.unmigrated_count" => unmigrated_count,
            "gh.registry.failed_count" => failed_count,
          )

          migration_run = Registry::PackagesMigration.find_by_state(:inProgress)
          return if migration_run.nil?

          if unmigrated_count == 0  # all versions of a package are migrated
            migration_run.update(success_pkg_count: migration_run.success_pkg_count + 1)
          elsif unmigrated_count == failed_count  # some versions have failed when package migration has completed
            migration_run.update(failed_pkg_count: migration_run.failed_pkg_count + 1)
          end

          migrated_pkg_count = migration_run.success_pkg_count + migration_run.failed_pkg_count

          if migration_run.total_pkg_count > migrated_pkg_count && migrated_pkg_count % 5 == 0
            channel = GitHub::WebSocket::Channels.packages_migration(migration_run.id)
            GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
          end
        end

        # Only add the namespace to the migrated feature flag if all packages have been migrated (for dotcom)
        # Update migration_state to migrated in DB only if all packages have been migrated (for enterprise)
        def update_migration_flag_or_state_if_migrated(msg)
          owner = msg&.package&.owner
          return if owner.nil?

          unmigrated_count = Registry::PackageVersion.joins(:package)
            .where(
              package: {
                owner_id: owner.id,
                package_type: msg.package_type
              }
            )
            .unmigrated
            .count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.owner_id" => owner.id,
            "gh.registry.package_type" => msg.package_type,
            "gh.registry.unmigrated_count" => unmigrated_count,
          )

          # if any namespace migration completed with error, increment the failed org count by 1
          if unmigrated_count > 0
            return if !GitHub.enterprise?
            failed_count = Registry::PackageVersion.joins(:package)
              .where(
                package: {
                  owner_id: owner.id,
                  package_type: msg.package_type
                }
              )
              .migratable(msg.package_type, error_only: true)
              .count

            GitHub.logger.info(
              "code.function" => __method__,
              "code.namespace" => self.class.name,
              "gh.registry.failed_count" => failed_count,
            )

            if unmigrated_count == failed_count
              migration_run = Registry::PackagesMigration.find_by_state(:inProgress)
              return if migration_run.nil?
              migration_run.update(failed_org_count: migration_run.failed_org_count + 1)
              if migration_run.success_org_count + migration_run.failed_org_count == migration_run.total_org_count
                migration_run.update(state: :completed)
                log_migration_complete(migration_run)
                channel = GitHub::WebSocket::Channels.packages_migration("package_settings")
                GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
              end
            end

            return
          end

          if msg.package_type == "npm" || msg.package_type == "nuget" || msg.package_type == "rubygems"
            Registry::OwnerMigration.find_by(owner_id: owner.id, package_type: msg.package_type).update(state: :migrated)
            GlobalInstrumenter.instrument("package_registry.namespace_cache_invalidate",
              { namespace: owner.name, ecosystem: msg.package_type })
          elsif msg.package_type == "docker"
            if GitHub.enterprise?
              Registry::OwnerMigration.upsert({ owner_id: owner.id, package_type: msg.package_type, state: :migrated })
              # if any namespace migration completed successfully, increment the successful org count by 1
              migration_run = Registry::PackagesMigration.find_by_state(:inProgress)
              return if migration_run.nil?
              migration_run.update(success_org_count: migration_run.success_org_count + 1)

              if migration_run.success_org_count + migration_run.failed_org_count == migration_run.total_org_count
                migration_run.update(state: :completed)
                log_migration_complete(migration_run)
                channel = GitHub::WebSocket::Channels.packages_migration("package_settings")
                GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
              end
            else
              owner.disable_feature(:packages_docker_v1_migration_in_process)
            end
          end
        end

        def log_migration_complete(migration_run)
          GitHub.logger.info(
            "Registry packages migration finished",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.triggered_by" => migration_run.owner.login,
            "gh.registry.owner_id" => migration_run.owner.id,
            "gh.registry.total_org_count" => migration_run.total_org_count,
            "gh.registry.success_org_count" => migration_run.success_org_count,
            "gh.registry.failed_org_count" => migration_run.failed_org_count,
            "gh.registry.total_pkg_count" => migration_run.total_pkg_count,
            "gh.registry.success_pkg_count" => migration_run.success_pkg_count,
            "gh.registry.failed_pkg_count" => migration_run.failed_pkg_count,
          )
        end

        def enqueue_migration_if_new_push_detected(msg)
          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.last_migrated_package_id" => msg.last_migrated_package_id,
            "gh.registry.last_migrated_version_id" => msg.last_migrated_version_id,
          )
          if msg.last_migrated_package_id > 0
            enqueue_migrate_namespace_job_if_new_package_pushed(msg)
          end
          if msg.last_migrated_version_id > 0
            enqueue_migrate_package_job_if_new_version_pushed(msg)
          end
        end

        def enqueue_migrate_namespace_job_if_new_package_pushed(msg)
          return if msg.last_migrated_package_id.nil? || msg.last_migrated_package_id <= 0

          unmigrated_count = Registry::Package
            .migratable(msg.package_type)
            .where(owner_id: msg.package.owner_id)
            .where("registry_packages.id > ?", msg.last_migrated_package_id)
            .count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.unmigrated_count" => unmigrated_count,
          )

          if unmigrated_count > 0
            ::Packages::Migration::MigrateNamespaceJob.perform_later(msg.package.owner.login, msg.package_type, force: msg.is_forced)
          end
        end

        def enqueue_migrate_package_job_if_new_version_pushed(msg)
          return if msg.last_migrated_version_id.nil? || msg.last_migrated_version_id <= 0

          unmigrated_count = msg
            .package
            .package_versions
            .migratable(msg.package_type)
            .where("id > ?", msg.last_migrated_version_id)
            .count

          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.unmigrated_count" => unmigrated_count,
          )

          if unmigrated_count > 0
            ::Packages::Migration::MigratePackageJob.perform_later(msg.package.id, force: msg.is_forced)
          end
        end

        # Only enqueues the DockerMigrationResetBillingOwnerJob if the namespace is migrated
        def enqueue_reset_docker_billing_job_if_migrated(msg)
          return if (owner = msg&.package&.owner).nil?

          unmigrated_count = Registry::PackageVersion.joins(:package)
            .where(
              package: {
                owner_id: owner.id,
                package_type: "docker"
              }
            )
            .unmigrated
            .count

          if unmigrated_count == 0
            ::Packages::DockerMigrationResetBillingOwnerJob.perform_later(owner_id: owner.id)
          end
        end

        # Wrapper around GitHub::StreamProcessors::Message
        class VersionMigrationStatusMessage < SimpleDelegator

          def initialize(msg)
            super
            {
              invalid_migration_state: -> { migration_state.nil? },
              missing_version_id: -> { version_id == 0 },
              version_not_found: -> { version.nil? },
              migration_already_complete: -> { version.migration_state == "complete" },
              migration_not_initiated: -> { version.migration_state != "pending" },
              package_not_found: -> { package.nil? },
              invalid_package_type: -> { !(package&.package_type.in?(%w[docker npm rubygems nuget])) },
              repo_not_found: -> { repo.nil? },
            }
            .each { |reason, condition| return skip(reason) if condition.call }
          end

          #Here we are evaluating if this versions SHA has been updated while it was in pending migration state
          #If it has been updated then this is a new push and we should update the version migration state again to unmigrated
          #So that it can be synced with V2 registry
          def should_remigrate_version
            version_last_updated_at ||= value.dig(:version_last_updated_at, :seconds)
            @should_remigrate_version ||= Time.at(version_last_updated_at).to_datetime < version&.updated_at
          end

          def migration_state
            @migration_state ||= { COMPLETE: "complete", ERROR: "error", RETRIABLE_ERROR: "retriable_error" }.dig(value.dig(:migration_state))
          end

          def migrated_package_id
            @migrated_package_id ||= value.fetch(:migrated_package_id, 0)
          end

          def version_id
            @version_id ||= value.fetch(:version_id, 0)
          end

          def version
            @version ||= Registry::PackageVersion.throttle_with_retry(max_retry_count: 5) do
              Registry::PackageVersion.find_by_id(version_id)
            end
          end

          def package
            version&.package
          rescue ActiveRecord::RecordNotFound
            nil
          end

          def package_type
            package&.package_type
          end

          def is_docker?
            package_type == "docker"
          end

          def repo
            package&.repository
          rescue ActiveRecord::RecordNotFound
            nil
          end

          def is_forced
            @is_forced ||= value.fetch(:is_forced, false)
          end

          def last_migrated_version_id
            @last_migrated_version_id ||= value.fetch(:last_migrated_version_id, 0)
          end

          def last_migrated_package_id
            @last_migrated_package_id ||= value.fetch(:last_migrated_package_id, 0)
          end
        end
      end
    end
  end
end
