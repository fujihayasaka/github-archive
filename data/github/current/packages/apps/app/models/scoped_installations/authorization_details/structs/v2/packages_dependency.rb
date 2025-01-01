# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::PackagesDependency
        extend T::Helpers

        requires_ancestor { V2 }

        sig { params(package: PackageRegistry::PackageSubject).void }
        def remove_package_permission(package)
          subject_id = package.id
          resource_type = ResourceType::PackageRegistry
          access_type = package.access_type.to_s

          action, permission =
            case access_type
            when "administration"
              [Permission::ActionString::Write, access_type]
            else
              [Permission::ActionString::Read, access_type]
            end

          resource_selection = self.get(resource_type)
          existent_subject_ids = resource_selection.permissions[permission]&.fetch(action, [])
          return unless existent_subject_ids&.include?(subject_id)

          resource_selection.permissions[permission][action].delete(subject_id)
          remove_blank_properties(resource_selection, permission, action)
        end

        private

        sig do
          params(
            resource_selection: ScopedInstallations::AuthorizationDetails::Structs::V2::ResourceSelection,
            permission: String,
            action: Permission::ActionString
          ).void
        end
        def remove_blank_properties(resource_selection, permission, action)
          subject_ids = resource_selection.permissions[permission][action]
          return unless subject_ids.blank?

          resource_selection.permissions[permission].delete(action)

          actions = resource_selection.permissions[permission]
          return unless actions.blank?

          resource_selection.permissions.delete(permission)

          self.package = nil if resource_selection.permissions.blank?
        end
      end
    end
  end
end
