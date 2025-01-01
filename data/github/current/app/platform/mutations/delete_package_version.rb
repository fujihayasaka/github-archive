# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeletePackageVersion < Platform::Mutations::Base
      description "Delete a package version."
      minimum_accepted_scopes ["delete:packages", "read:packages"]

      visibility :public, environments: [:enterprise, :dotcom]

      argument :package_version_id, ID, "The ID of the package version to be deleted.", required: true, loads: Objects::PackageVersion

      field :success, Boolean, "Whether or not the operation succeeded.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, package_version:)
        package_version.async_package.then do |package|
          permission.async_repo_and_org_owner(package).then do |repo, org|
            permission.access_allowed?(
              :delete_package,
              repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          end
        end
      end

      def resolve(package_version:)
        if package_version.restrict_graphql_apis?
          raise Errors::Unprocessable.new("#{package_version.package.registry_package_type} registry is not supported by GraphQL APIs.")
        end
        if package_version.deleted?
          raise Platform::Errors::NotFound.new("No PackageVersion with ID: #{package_version.global_relay_id} found.")
        end

        via_actions = context[:integration].respond_to?(:launch_github_app?) &&
          (context[:integration].launch_github_app? || context[:integration].launch_lab_github_app?)

        package_version.delete!(
          actor: context[:viewer],
          via_actions: via_actions,
          user_agent: GitHub.context[:user_agent].to_s,
        )

        { success: true }
      rescue Registry::PackageVersion::PublicVersionDeletionError => e
        raise Errors::Unprocessable.new(e)
      rescue ActiveRecord::RecordInvalid => e
        Failbot.report(e)
        raise Errors::Unprocessable.new("Could not delete PackageVersion with ID: #{package_version.global_relay_id}.")
      end
    end
  end
end
