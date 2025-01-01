# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPackageTag < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      description "Adds a new tag to a package version."
      visibility :internal

      minimum_accepted_scopes ["write:packages"]
      argument :owner, String, "The login of the package owner", required: true
      argument :package_name, String, "The name of the package.", required: true
      argument :package_type, Enums::PackageType, "The type of the package.", required: true
      argument :version, String, "The version to add the tag to.", required: true
      argument :tag, String, "The tag name.", required: true

      field :package, Objects::Package, "The package of the newly added tag.", null: true
      field :viewer, Objects::User, "The user that created the package version metadata.", null: true
      field :result, Objects::PackagesMutationResult, "The result of the mutation, success or failure, with user-safe details.", null: false

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        owner = User.find_by_login(inputs[:owner])
        raise Errors::NotFound.new("Could not find an account with login \"#{inputs[:owner]}\".") unless owner
        package = owner.packages.with_name_and_type(inputs[:package_name], inputs[:package_type], inputs[:package_type])
        raise Errors::NotFound.new("Could not find a matching package.") unless package
        repository = package.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:create_package, current_org: org, repo: repository, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(**inputs)
        package = ::Platform::Helpers::PackageQuery.get_package(inputs, context)

        result = check_repository_prerequisites(repository: package.repository, actor: context[:viewer])
        unless result[:success]
          return {
            package: nil,
            viewer: context[:viewer],
            result: result,
          }
        end

        version = package.package_versions.where(version: inputs[:version]).first
        unless version && !version.deleted?
          raise Errors::NotFound.new("No such version \"#{inputs[:version]}\" on the package.")
        end

        tag = nil
        tag_existed = false

        Registry::Tag.transaction do
          tag = Registry::Tag.where(
            name: inputs[:tag],
            registry_package_id: package.id,
          ).first
          if tag.nil?
            Registry::Tag.create!(
              name: inputs[:tag],
              registry_package_id: package.id,
              registry_package_version_id: version.id,
            )
          else
            tag_existed = true
            tag.update!(registry_package_version_id: version.id)
          end
        end

        {
          package: package,
          viewer: context[:viewer],
          result: {
            success: true,
            user_safe_status: tag_existed ? :accepted : :created,
            user_safe_message: "Tag \"#{inputs[:tag]}\" was applied.",
            validation_errors: [],
          },
        }
      rescue ActiveRecord::ActiveRecordError
        {
          package: nil,
          viewer: context[:viewer],
          result: {
            success: false,
            user_safe_status: :unprocessable_entity,
            user_safe_message: "The package version was not tagged.",
            error_type: "validation",
            validation_errors: tag.present? ? Platform::UserErrors.mutation_errors_for_model(tag) : [],
          },
        }
      end
    end
  end
end
