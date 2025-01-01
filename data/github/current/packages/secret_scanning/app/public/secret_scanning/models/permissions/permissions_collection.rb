# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Permissions
      class PermissionsCollection < T::Struct
        const :groups, T::Hash[String, T::Array[Permission]], default: {}
        const :group_label, String
        const :value_label, String

        sig { params(group: String, permission: Permission).void }
        def add_permission(group, permission)
          groups[group] ||= []
          T.must(groups[group]) << permission
        end

        sig { params(group: String, permission: String).void }
        def mark_permission_in_group_as_deleted(group, permission)
          if groups[group].present?
            T.must(groups[group]).each do |p|
              if p.value == permission
                p.deleted = true
              end
            end
          end
        end

        sig { params(permission: String).void }
        def mark_permission_anywhere_as_deleted(permission)
          groups.each do |_, permissions|
            permissions.each do |p|
              if p.value == permission
                p.deleted = true
              end
            end
          end
        end
      end
    end
  end
end
