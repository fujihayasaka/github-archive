# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V1::PackagesDependency
        extend T::Helpers

        requires_ancestor { V1 }

        sig { params(package: PackageRegistry::PackageSubject).void }
        def remove_package_permission(package)
          subject_id = package.id
          resource_type = ResourceType::PackageRegistry
          access_type = package.access_type.to_s

          action, permission =
            case access_type
            when "administration"
              ["write", access_type]
            when "contents"
              ["read", access_type]
            end

          return unless action
          existent_subject_ids = self.asymmetric_for(resource_type).dig(permission, action)
          return unless existent_subject_ids&.include?(subject_id)

          T.must(T.must(T.must(T.must(self.asymmetric)[resource_type])[permission])[action]).delete(subject_id)
          remove_blank_properties(resource_type, permission, action)
        end

        private

        sig { params(resource_type: ResourceType, permission: String, action: String).void }
        def remove_blank_properties(resource_type, permission, action)
          subject_ids = self.asymmetric&.dig(resource_type, permission, action)
          return unless subject_ids.blank?

          T.must(T.must(T.must(self.asymmetric)[resource_type])[permission]).delete(action)

          actions = self.asymmetric&.dig(resource_type, permission)
          return unless actions.blank?

          T.must(T.must(self.asymmetric)[resource_type]).delete(permission)

          permissions = self.asymmetric&.dig(resource_type)
          return unless permissions.blank?

          T.must(self.asymmetric).delete(resource_type)
          self.asymmetric = nil if self.asymmetric&.empty?
        end
      end
    end
  end
end
