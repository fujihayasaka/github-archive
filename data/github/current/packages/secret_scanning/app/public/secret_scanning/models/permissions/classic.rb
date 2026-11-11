# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Permissions
      class Classic < T::Struct
        const :all_scopes, T::Array[String]
        const :scopes_with_parents, T::Hash[String, T::Array[String]]

        sig { returns(Models::Permissions::PermissionsCollection) }
        def to_permissions_collection
          permissions_collection = Models::Permissions::PermissionsCollection.new(group_label: "Target", value_label: "Permission")

          self.scopes_with_parents.each do |target, values|
            permissions_collection.groups[target] = values.map do |value|
              Models::Permissions::Permission.new(value: value, group: target)
            end
          end

          permissions_collection
        end
      end
    end
  end
end
