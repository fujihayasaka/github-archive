# typed: strict
# frozen_string_literal: true

# Internal: Access only through individual subjects. These subjects don't have a
# 'selection' as we only grant direct/'subset' access.
#
# This is only used internally by apps like Actions and Codespaces.
#
# Examples:
#
#  SubjectIdsOnlySelection.new(
#    permissions: {
#      "sarifs" => {
#        Permission::ActionString::Read => [42, 50, 79]
#      }
#    }
#  )
module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V2
        class SubjectIdsOnlySelection < T::Struct
          extend T::Sig

          include ResourceSelection
          extend ResourceSelectionDefaultable

          ActionToSubjectIdsHash = T.type_alias do
            T::Hash[Permission::ActionString, T::Array[Integer]]
          end

          prop :permissions, T::Hash[String, ActionToSubjectIdsHash]

          sig { override.returns(V2::SubjectIdsOnlySelection) }
          def self.default_value
            new(permissions: {})
          end

          sig { override.params(name: String).returns(NilClass) }
          def granted_access_on_all_subjects(name); end

          sig { override.params(name: String, subject_ids: T::Array[Integer]).returns(PublicMethods::SubjectIdActionPairs) }
          def granted_subject_ids_with_actions_for(name, subject_ids)
            granted = permissions[name]
            return [] if granted.nil?

            granted.each_with_object({}) do |(action_string, ids), hash|
              action = action_string.to_i

              (ids & subject_ids).each do |id|
                hash[id] = [hash[id].to_i, action].max
              end
            end.to_a
          end

          sig { override.returns(T::Array[Integer]) }
          def selection
            permissions.flat_map do |_, actions_resources_and_subject_ids|
              actions_resources_and_subject_ids.flat_map do |_, subject_ids|
                subject_ids
              end
            end.uniq
          end

          sig do
            override.params(
              permissions: T::Hash[String, Symbol],
              selection: T.any(Selection, T::Array[Integer])
            ).void
          end
          def add_permissions_selection(permissions:, selection:)
            subject_ids = T.cast(selection, T::Array[Integer])

            permissions.each do |name, action|
              action = Permission::ActionString.deserialize(action.to_s)
              action_for_subject_ids = { action => subject_ids }

              if self.permissions[name].blank?
                self.permissions[name] = action_for_subject_ids
              else
                current_subject_ids = self.permissions.dig(name, action) || []
                T.must(self.permissions[name])[action] = current_subject_ids | subject_ids
              end
            end
          end

        end
      end
    end
  end
end
