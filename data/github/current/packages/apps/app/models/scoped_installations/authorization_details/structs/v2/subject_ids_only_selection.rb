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

          sig do
            override.params(
              name: String,
              subject_ids: T.nilable(PublicMethods::SubjectIds)
            ).returns(PublicMethods::SubjectIdActionPairs)
          end
          def granted_subject_ids_with_actions_for(name, subject_ids)
            granted = permissions[name]
            return [] if granted.nil?

            granted.each_with_object({}) do |(action_string, ids), hash|
              action = action_string.to_i

              filtered_ids = subject_ids.is_a?(Array) ? ids & subject_ids : ids

              filtered_ids.each do |id|
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

          sig { override.returns(T::Array[Authzd::Proto::Attribute]) }
          def authzd_proto_attributes
            attributes = Hash.new { |h, k| h[k] = [] }

            self.permissions.keys.each do |resource|
              self.granted_subject_ids_with_actions_for(resource, nil).each do |subject_id, action|
                Permission::Action.deserialize(action).expand.map do |expanded|
                  key = "#{resource}.#{expanded}.ids"
                  attributes[key] << subject_id
                end
              end
            end

            attributes.map do |name, value|
              Authzd::Proto::Attribute.wrap(name, value.uniq)
            end
          end
        end
      end
    end
  end
end
