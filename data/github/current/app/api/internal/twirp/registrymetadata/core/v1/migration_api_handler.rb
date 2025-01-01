# typed: false
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::MigrationAPIService
      class MigrationAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::MigrationAPIService

        # In Proxima we are only using V2 implementation and will not be using migrations
        exempt_from_tenant_context_requirement

        # Public: Implementation of the GetPackageMigrationStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetPackageMigrationStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetPackageMigrationStatusResponse, or a Twirp::Error.
        def get_package_migration_status(req, env)
          repo = Repository.with_name_with_owner(req.repo_name_with_owner)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          owner = repo.owner
          return Twirp::Error.not_found("owner not found") if owner.nil?

          package_type = Registry::Package.package_types.key(Registry::Package.package_types[:docker])
          package = repo.packages.with_name_and_type(req.package_name, package_type, package_type)

          #here we are checking if the package which is being pushed is completely pushed or not
          #In V1 docker when a package is pushed it creates dummy docker-base-layer and push all the layers against that
          #and once all layer are uploaded it will create new entry for version and set the file-count from docker-base-layer file count
          #after that docker-base-layer count is set to 0
          is_real_version_exists = package.has_versions_excluding_base_layer? if !package.nil?

          return Twirp::Error.not_found("package not found") if package.nil? || !is_real_version_exists

          return Twirp::Error.failed_precondition("package is not migratable") unless package.migratable?

          migration_status = package.migrated? ? :MIGRATION_STATUS_COMPLETE : :MIGRATION_STATUS_PENDING

          {
            package_id: package.id,
            owner_id: owner.id,
            repo_id: repo.id,
            status: migration_status,
          }
        end

        # Public: Implementation of the GetOwnerMigrationStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetOwnerMigrationStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetOwnerMigrationStatusResponse, or a Twirp::Error.
        def get_owner_migration_status(req, env)
          return Twirp::Error.unimplemented("not implemented") if !GitHub.enterprise?

          owner = User.find_by_login(req.owner_name)
          return Twirp::Error.not_found("owner not found") if owner.nil?

          # If owner type is of type User then we should return from here
          # This is beacuse we don't support migration of user level packages in GHES-3.6
          return Twirp::Error.invalid_argument("owner must be an organization") if owner.type == "User"

          package_type = Registry::Package.package_types.key(Registry::Package.package_types[:docker])
          owner_state = Registry::OwnerMigration.where(owner_id: owner.id, package_type: package_type).pick(:state)
          migration_status = :MIGRATION_STATUS_INVALID

          if owner_state.nil?
            state = Registry::PackagesMigration.order(id: :desc).pick(:state)

            if state.nil?
              return Twirp::Error.not_found("migration status not found")
            end

            case Registry::PackagesMigration.states[state]
            when Registry::PackagesMigration.states[:completed]
              migration_status = :MIGRATION_STATUS_COMPLETE
            when Registry::PackagesMigration.states[:inProgress]
              if Registry::Package
                  .where(owner_id: owner.id)
                  .where("registry_packages.package_type = 3 OR registry_packages.registry_package_type = 'docker'")
                  .exists?
                migration_status = :MIGRATION_STATUS_PENDING
              else
                migration_status = :MIGRATION_STATUS_COMPLETE
              end
            end
          else
            migration_status = migration_status_from_state(owner_state)
          end

          {
            owner_id: owner.id,
            status: migration_status,
          }
        end

        # Public: Implementation of the GetPackageVersionMigrationStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetPackageVersionMigrationStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetPackageVersionMigrationStatusResponse, or a Twirp::Error.
        def get_package_version_migration_status(req, env)
          repo = Repository.with_name_with_owner(req.repo_name_with_owner)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          owner = repo.owner
          return Twirp::Error.not_found("owner not found") if owner.nil?

          package_type = Registry::Package.package_types.key(Registry::Package.package_types[:docker])
          package = repo.packages.with_name_and_type(req.package_name, package_type, package_type)

          return Twirp::Error.not_found("package not found") if package.nil?

          return Twirp::Error.failed_precondition("package is not migratable") unless package.migratable?

          #dont change the sequence of arguments here, these fileds are indexed in order
          version = Registry::PackageVersion.find_by(registry_package_id: package.id, version: req.tag_name, platform: "docker")
          return Twirp::Error.not_found("version not found") if version.nil?


          {
            package_id: package.id,
            owner_id: owner.id,

            repo_id: repo.id,
            status: format_version_status(version.migration_state),
          }
        end

        def format_version_status(status)
          case status
          when "unmigrated"
            "PACKAGE_VERSION_MIGRATION_STATUS_UNMIGRATED"
          when "pending"
            "PACKAGE_VERSION_MIGRATION_STATUS_PENDING"
          when "error"
            "PACKAGE_VERSION_MIGRATION_STATUS_ERROR"
          when "complete"
            "PACKAGE_VERSION_MIGRATION_STATUS_COMPLETE"
          when "retriable_error"
            "PACKAGE_VERSION_MIGRATION_STATUS_RETRIABLE_ERROR"
          else
            "PACKAGE_VERSION_MIGRATION_STATUS_INVALID"
          end
        end

        def migration_status_from_state(state)
          case Registry::OwnerMigration.states[state]
          when Registry::OwnerMigration.states[:inProgress]
            :MIGRATION_STATUS_PENDING
          when Registry::OwnerMigration.states[:migrated]
            :MIGRATION_STATUS_COMPLETE
          when Registry::OwnerMigration.states[:error]
            :MIGRATION_STATUS_ERROR
          when Registry::OwnerMigration.states[:retriableError]
            :MIGRATION_STATUS_ERROR
          else
            :MIGRATION_STATUS_INVALID
          end
        end

        # Public: Implementation of the GetPackageMigrationStatusEco Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetPackageMigrationStatusEcoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetPackageMigrationStatusEcoResponse, or a Twirp::Error.
        def get_package_migration_status_eco(req, env)
          owner = User.find_by_login(req.owner_name)

          return Twirp::Error.not_found("owner not found") if owner.nil?

          package = owner.packages.with_name_and_type(req.package_name, req.package_type, req.package_type)
          return Twirp::Error.not_found("package not found") if package.nil?

          return Twirp::Error.failed_precondition("package is not migratable") unless package.migratable?

          migration_status = package.migrated? ? :MIGRATION_STATUS_COMPLETE : :MIGRATION_STATUS_PENDING

          {
            package_id: package.id,
            owner_id: owner.id,
            status: migration_status,
          }
        end

        # Public: Implementation of the GetOwnerMigrationStatusEco Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetOwnerMigrationStatusEcoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetOwnerMigrationStatusEcoResponse, or a Twirp::Error.
        def get_owner_migration_status_eco(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            return Twirp::Error.unimplemented("not implemented") if GitHub.enterprise?

            owner = User.find_by_login(req.owner_name)
            registry_package_type = req.package_type
            check_new_namespace = req.check_new_namespace

            return Twirp::Error.not_found("owner not found") if owner.nil?

            if registry_package_type.empty?
              return Twirp::Error.invalid_argument("package_type should be non-empty", argument: "package_type")
            end

            # In registry_packages table, registry_package_type is "nuget", "npm", etc
            # and package_type is 0, 1, 2, etc

            package_type = Registry::Package.package_types[registry_package_type]
            if package_type.nil? || package_type == Registry::Package.package_types[:docker]
              return Twirp::Error.invalid_argument("invalid package_type", argument: "package_type")
            end

            owner_migration_record = Registry::OwnerMigration.find_by(owner_id: owner.id, package_type: package_type)
            owner_migration_state = migration_status_from_state(owner_migration_record&.state)
            # consider new namespace as migrated for publish
            if check_new_namespace && owner_migration_state == :MIGRATION_STATUS_INVALID
              package_count = owner.packages.migratable(registry_package_type, unmigrated_only: false).count
              if package_count == 0
                owner_migration_state = :MIGRATION_STATUS_COMPLETE
                # enable feature flag for new namespace
                if registry_package_type == "maven"
                  owner.enable_feature_flag(:packages_maven_registry_v2) # rubocop:disable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
                end
                # create record for new namespace so that downloads do not consider it as unmigrated
                ActiveRecord::Base.connected_to(role: :writing) do
                  Registry::OwnerMigration.upsert({ owner_id: owner.id, package_type: package_type, state: :migrated })
                end
                # invalidate namespace cache as it might be set due to previous non-upload requests
                GlobalInstrumenter.instrument("package_registry.namespace_cache_invalidate", { namespace: owner.name, ecosystem: registry_package_type })
              end
            end
            {
              owner_id: owner.id,
              status: owner_migration_state,
            }
          end
        end
      end
    end
  end
end
