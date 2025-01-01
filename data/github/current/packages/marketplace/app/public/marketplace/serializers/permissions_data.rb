# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class PermissionsData
      include T::Helpers
      include GitHub::Memoizer

      sig { returns(Integration) }
      attr_reader :integration

      sig { params(integration: Integration).void }
      def initialize(integration:)
        @integration = integration
      end

      sig { returns(T::Array[Marketplace::Types::SerializedPermissionsData]) }
      def call
        data = []
        data << single_file_data(repository_permissions)
        data << permissions_data("repository", repository_permissions)
        data << permissions_data("organization", latest_version.permissions_of_type(Organization))
        data << permissions_data("user", latest_version.permissions_of_type(User))
        data.compact_blank.flatten
      end

      private

      sig { returns(IntegrationVersion) }
      memoize def latest_version
        integration.latest_version
      end

      sig { returns(T::Hash[String, Symbol]) }
      memoize def repository_permissions
        latest_version.permissions_of_type(::Repository)
      end

      sig { params(permissions: T::Hash[String, Symbol]).returns(T::Array[Marketplace::Types::SerializedPermissionsData]) }
      def single_file_data(permissions)
        permissions_level = permissions["single_file"].to_s
        paths = latest_version.single_file_paths
        return [] unless permissions_level.present? && paths.present?

        [{
          scope: "single file",
          permissionLevel: permissions_level,
          values: paths
        }]
      end

      sig do
        params(
          scope: String,
          permissions: T::Hash[String, Symbol]
        ).returns(T::Array[Marketplace::Types::SerializedPermissionsData])
      end
      def permissions_data(scope, permissions)
        [:read, :write, :admin].each_with_object([]) do |permission_level, memo|
          values = human_readable_values(permissions, permission_level)
          memo << {
            scope: scope,
            permissionLevel: permission_level.to_s,
            values: values
          } if values.present?
        end
      end

      sig { params(permissions: T::Hash[String, Symbol], action: Symbol).returns(T::Array[String]) }
      def human_readable_values(permissions, action)
        applicable_permissions = permissions.select { |k, v| v == action && k != "single_file" }.keys
        names = Permissions::FineGrainedResources::Metadata.human_readable_resource_names.values_at(*applicable_permissions)
        names.compact.sort
      end
    end
  end
end
