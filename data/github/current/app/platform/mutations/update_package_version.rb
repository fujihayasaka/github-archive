# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePackageVersion < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      description "Updates a package version."
      visibility :internal
      minimum_accepted_scopes ["write:packages"]

      argument :version_id, ID, "The package version ID to update.", required: true, loads: Objects::PackageVersion, as: :package_version
      argument :sha256, String, "The sha256 hash of the package_version.", required: false
      argument :dependencies, [Inputs::PackageDependencyAttributes], "The dependencies of the package.", required: false
      argument :size, Integer, "The size of the package_version.", required: false
      argument :readme, String, "The readme for this package version.", required: false
      argument :summary, String, "The summary for this package version.", required: false
      argument :manifest, String, "The package manifest for this package version.", required: false
      argument :platform, String, "The platform this version was built for.", required: false
      argument :installation_command, String, "A single line of text to install this package version.", required: false
      argument :restore_if_deleted, Boolean, "Restore this version if deleted, true or false.", required: false, default_value: false

      field :package_version, Objects::PackageVersion, "The updated package version.", null: true
      field :viewer, Objects::User, "The user that created the package version.", null: true
      field :result, Objects::PackagesMutationResult, "The result of the mutation, success or failure, with user-safe details.", null: false

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, package_version:, **inputs)
        repository = package_version.package.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:create_package, current_org: org, repo: repository, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(package_version:, **inputs)
        repository = package_version.package.repository

        result = check_repository_prerequisites(repository: repository, actor: context[:viewer])
        unless result[:success]
          return {
            package_version: nil,
            viewer: context[:viewer],
            result: result,
          }
        end

        # If there was already a value for manifest, then this is an update.
        was_manifest_created = package_version.manifest.to_s.empty? && inputs.key?(:manifest)

        Registry::PackageVersion.transaction do
          package_version.sha256 = inputs[:sha256] if inputs.key?(:sha256)
          package_version.size = inputs[:size] if inputs.key?(:size)
          package_version.manifest = inputs[:manifest] if inputs.key?(:manifest)
          package_version.platform = inputs[:platform] if inputs.key?(:platform)
          package_version.metadata.set(Registry::Metadatum::KEYS[:SUMMARY], inputs[:summary]) if inputs.key?(:summary)
          package_version.metadata.set(Registry::Metadatum::KEYS[:README], inputs[:readme]) if inputs.key?(:readme)
          if inputs.key?(:installation_command)
            raise Errors::Validation.new("Installation command is too long (>500 characters)") if inputs[:installation_command].length > 500
            package_version.metadata.set(Registry::Metadatum::KEYS[:INSTALLATION_COMMAND], inputs[:installation_command])
          end

          # Clear out existing package version dependencies and set new ones.
          if inputs[:dependencies].present?
            package_version.dependencies.destroy_all
            inputs[:dependencies].each do |dependency_attrs|
              package_version.dependencies.build(
                name: dependency_attrs[:name],
                version: dependency_attrs[:version],
                dependency_type: dependency_attrs[:dependency_type],
              )
            end
          end

          if package_version.deleted? && inputs[:restore_if_deleted]
            package_version.restore!(actor: context[:viewer])
          end

          raise Errors::Validation.new unless package_version.save
        end

        if inputs.key?(:manifest)
          # viewer might be a type of installation, if so the bot associated should be the actor
          actor_id = context[:viewer].try(:bot)&.id || context[:viewer].id

          if was_manifest_created
            package_version.trigger_create_webhook(actor_id)
          else
            package_version.trigger_update_webhook(actor_id)
          end

          hydro_params = {
            repository: repository,
            registry_package_id: package_version.package.id,
            version: package_version.version,
            actor: context[:viewer],
            action: "PUBLISHED",
            user_agent: GitHub.context[:user_agent].to_s,
          }

          GlobalInstrumenter.instrument("package.published", hydro_params)
        end

        {
          package_version: package_version,
          viewer: context[:viewer],
          result: {
            success: true,
            user_safe_status: :accepted,
            user_safe_message: "Package version updated.",
            error_type: "none",
            validation_errors: [],
          },
        }
      rescue Errors::Validation => err
        {
          package_version: nil,
          viewer: context[:viewer],
          result: {
            success: false,
            user_safe_status: :unprocessable_entity,
            user_safe_message: err.message.present? ? err.message : "The package version couldn't be updated.",
            error_type: "validation",
            validation_errors: Platform::UserErrors.mutation_errors_for_model(package_version),
          },
        }
      end

    end
  end
end
