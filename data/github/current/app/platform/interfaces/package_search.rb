# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module PackageSearch
      include Platform::Interfaces::Base
      description "Represents an interface to search packages on an object."

      visibility :internal

      global_id_field :id, description: "The Node ID of the PackageSearch object"

      field :packages_for_query, Connections.define(::Platform::Objects::Package), null: false, visibility: :internal do
        description "A list of packages for a particular search query."

        argument :query, String, "Find packages by search query.", required: false
        argument :package_type, Enums::PackageType, "Filter packages by type.", required: false
      end

      def packages_for_query(query: nil, package_type: nil)
        packages = nil
        v1_packages = []
        v2_packages = []
        if query.present?
          query_type = "RegistryPackages"

          queries = Search::QueryHelper.new(query, query_type,
            current_user: context[:viewer],
            user_session: context[:user_session],
            highlight: false,
            owner: object,
            package_type: package_type,
            repo_id: @object.is_a?(Repository) ? @object.id : nil
          )

          query = queries[query_type]
          package_ids = query.execute.map(&:id)
          if !GitHub.enterprise? && package_type == "nuget"
            GitHub.logger.info(
              "Filtering migrated packages from query",
              "code.fucntion" => __method__,
              "code.namespace" => self.class.name,
              "gh.request_id" => GitHub.context[:request_id],
            )
            ## Retrive only v1 packages for now. don't include already migrated packages
            v2_ids, v1_ids = package_ids.partition { |id| id.start_with?("rms") }
            packages = object.packages.where(id: v1_ids)
            packages.map do |package|
              package.migrated? ? v2_packages.push(package) : v1_packages.push(package)
            end
            packages = v1_packages
          else
            packages = object.packages.where(id: package_ids)
          end
        else
          packages = object.packages.scoped
          if !GitHub.enterprise? && package_type == "nuget"
            GitHub.logger.info(
              "Filtering migrated packages",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
              "gh.request_id" => GitHub.context[:request_id],
            )
            packages = packages.where(package_type: package_type)
            packages.map do |package|
              package.migrated? ? v2_packages.push(package) : v1_packages.push(package)
            end
            packages = v1_packages
          end
        end


        loaded_packages  = if Platform.requires_scope?(context[:origin])
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
    end
  end
end
