# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Permissions
      class Fgp < T::Struct
        const :permissions, T::Hash[String, String]

        sig { params(permissions: T::Hash[String, Symbol]).returns(SecretScanning::Models::Permissions::Fgp) }
        def self.new_from_permissions(permissions)
          string_permissions = permissions.each_with_object({}) do |(key, value), hash|
            hash[key] = value.to_s
          end
          SecretScanning::Models::Permissions::Fgp.new(permissions: string_permissions)
        end

        sig { returns(Models::Permissions::PermissionsCollection) }
        def to_permissions_collection
          permissions_collection = Models::Permissions::PermissionsCollection.new(group_label: "Permission", value_label: "Target")
          self.permissions.each do |target, value|
            readable_group = Fgp.value_to_display_group(value)
            permissions_collection.add_permission(readable_group, Models::Permissions::Permission.new(value: target, group: readable_group))
          end

          permissions_collection
        end

        sig { params(value: String).returns(String) }
        def self.value_to_display_group(value)
          if value == "write"
            "Read and Write"
          elsif value == "read"
            "Read"
          else
            raise ArgumentError, "Invalid value: #{value}"
          end
        end
      end
    end
  end
end
