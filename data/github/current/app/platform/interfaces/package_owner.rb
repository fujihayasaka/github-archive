# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module PackageOwner
      MAX_IN_CLAUSE_SIZE = 10_000

      include Platform::Interfaces::Base
      description "Represents an owner of a package."

      visibility :public, environments: [:enterprise, :dotcom]

      global_id_field :id, description: "The Node ID of the PackageOwner object"

      field :packages, Connections.define(::Platform::Objects::Package), null: false do
        description "A list of packages under the owner."

        argument :name, String, "Find a package by name.", required: false, visibility: :internal
        argument :names, [String, null: true], "Find packages by their names.", required: false
        argument :repository_database_id, Integer, "Find packages in a repository by the repository's database ID.", required: false, visibility: :internal
        argument :repository_id, ID, "Find packages in a repository by ID.", required: false
        argument :repository_name_with_owner, String, "Find packages in a repository by the repository's nameWithOwner.", required: false, visibility: :internal
        argument :package_type, Enums::PackageType, "Filter registry package by type.", required: false
        argument :registry_package_type, String, "Filter registry package by type (string).", required: false, visibility: :internal
        argument :public_only, Boolean, "Filter packages by whether it is publicly visible", required: false, default_value: false, visibility: :internal
        argument :order_by, Inputs::PackageOrder, "Ordering of the returned packages.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
        argument :include_deleted, Boolean, "Filter registry package by whether it has been deleted", required: false, default_value: true, visibility: :internal
      end

      def packages(name: nil, names: nil, repository_database_id: nil, repository_id: nil, repository_name_with_owner: nil, package_type: nil, registry_package_type: nil, public_only: false, order_by:, include_deleted: true)
        packages = if name.present?
          object.packages.where(name: name)
        elsif names.present?
          object.packages.where(name: names)
        else
          object.packages.scoped
        end

        if package_type.present?
          if !GitHub.enterprise? && Registry::Package::BLOCKED_GRAPHQL_TYPES.include?(package_type)
            raise Errors::Unprocessable.new("#{package_type} registry is not supported by GraphQL APIs.")
          end
          if registry_package_type.present?
            packages = packages.where("package_type=? OR registry_package_type=?", Registry::Package.package_types[package_type], registry_package_type)
          else
            packages = packages.where(package_type: package_type)
          end
        end

        if repository_database_id.present?
          packages = packages.where(repository_id: repository_database_id)
        elsif repository_id.present?
          repo_db_id = Platform::Helpers::NodeIdentification.from_global_id(repository_id).last
          packages = packages.where(repository_id: repo_db_id)
        elsif repository_name_with_owner.present?
          owner_name, repo_name = repository_name_with_owner.split("/")
          owner_db_id = ::User.where(login: owner_name).pluck(:id).first
          repo_db_id = ::Repository.where(owner_id: owner_db_id, name: repo_name).order(active: :desc).pluck(:id).first
          packages = packages.where(repository_id: repo_db_id)
        end

        if order_by[:direction] == "ASC"
          packages = packages.order("created_at ASC")
        else
          packages = packages.order("created_at DESC")
        end

        unless include_deleted
          packages = packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted).distinct
        end

        if public_only
          repo_ids = packages.limit(MAX_IN_CLAUSE_SIZE + 1).distinct.pluck(:repository_id)
          raise Errors::Unprocessable.new("Filtering by public_only is not supported across more than #{MAX_IN_CLAUSE_SIZE} repositories") if repo_ids.length > MAX_IN_CLAUSE_SIZE

          repo_ids = ::Repository.where(id: repo_ids, public: true).pluck(:id)
          packages = packages.where(repository_id: repo_ids)
        end

        # remove packages where restrict_graphql_apis? is true
        packages = packages.select { |package| !package.restrict_graphql_apis? }

        loaded_packages = if Platform.requires_scope?(context[:origin])
          packages.map do |package|
            context[:permission].can_access?(package).then do |result|
              if result
                package
              else
                nil
              end
            end
          end
        else
          ::Platform::Helpers::PackageQuery.filter_packages_for_dotcom(packages, context[:viewer])
        end

        Promise.all(loaded_packages).then do |packages|
          ArrayWrapper.new(packages.compact)
        end
      end

      field :package, ::Platform::Objects::Package, null: true, visibility: :internal do
        description "A single package belonging to the owner."
        argument :id, ID, "The global ID of the package.", required: true
      end

      def package(id:)
        Helpers::NodeIdentification.async_typed_object_from_id([::Platform::Objects::Package], id, context).then do |package|
          next nil unless object.id == package.repository_id
          if package.restrict_graphql_apis?
            raise Errors::Unprocessable.new("#{package_type} registry is not supported by GraphQL APIs.")
          end
          package
        end
      end

      field :package_version, ::Platform::Objects::PackageVersion, null: true, visibility: :internal do
        description "A single package version belonging to the owner."
        argument :id, ID, "The global ID of the package version.", required: true
      end

      def package_version(id:)
        Helpers::NodeIdentification.async_typed_object_from_id([::Platform::Objects::PackageVersion], id, context).then do |version|
          version.async_package.then do |package|
            next nil unless object.id == package.repository_id
            version
          end
        end
      end
    end
  end
end
