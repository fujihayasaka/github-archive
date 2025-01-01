# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class CreatePackageVersionMetadata < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      description "Creates metadata on a package version."
      visibility :internal
      minimum_accepted_scopes ["write:packages"]

      argument :package_version_id, ID, "The package version to add package metadata.", required: true, loads: Objects::PackageVersion
      argument :metadata, [Inputs::PackageMetadatumTuple, null: true], "The metadatum value.", required: true

      field :package_version, Objects::PackageVersion, "The package version.", null: true
      field :viewer, Objects::User, "The user that created the package version metadata.", null: true
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
        raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{version_id}'.") if package_version.deleted?

        result = check_repository_prerequisites(repository: package_version.package.repository, actor: context[:viewer])
        unless result[:success]
          return {
            package_version: nil,
            viewer: context[:viewer],
            result: result,
          }
        end

        metadatum = nil

        Registry::Metadatum.transaction do
          inputs[:metadata].each do |input_metadatum|
            metadatum = nil
            metadatum = package_version.metadata.where(name: input_metadatum[:name]).first if input_metadatum[:update]
            metadatum ||= package_version.metadata.build(name: input_metadatum[:name])
            metadatum.value = input_metadatum[:value]
            raise Errors::Validation.new("Could not save metadatum : #{metadatum.errors.full_messages.join(", ")}") unless metadatum.save
          end
        end

        {
          package_version: package_version,
          viewer: context[:viewer],
          result: {
            success: true,
            user_safe_status: :created,
            user_safe_message: "Package version metadata created.",
            error_type: "none",
            validation_errors: [],
          },
        }
      rescue Errors::Validation
        {
          package_version: nil,
          viewer: context[:viewer],
          result: {
            success: false,
            user_safe_status: :unprocessable_entity,
            user_safe_message: "The package version metadata couldn't be created.",
            error_type: "validation",
            validation_errors: Platform::UserErrors.mutation_errors_for_model(metadatum),
          },
        }
      end
    end
  end
end
