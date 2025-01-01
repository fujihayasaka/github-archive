# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::GrantableDependency
        extend T::Sig
        extend T::Helpers

        requires_ancestor { V2 }
        requires_ancestor { Kernel }

        sig { returns(T::Hash[String, Symbol]) }
        def all_permissions
          T.bind(self, V2)

          self.properties.each_with_object({}) do |property, hash|
            value = public_send(property) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

            case value
            when V2::SelectionWithPermissions
              hash.merge!(value.permissions) do |_, old_value, new_value|
                [old_value, new_value].max
              end
            when V2::ElevatedAccessSelection, V2::SubjectIdsOnlySelection
              value.permissions.each_pair do |resource, access|
                case access
                when Permission::Action
                  hash.merge!(resource => access) do |_, old_value, new_value|
                    [old_value, new_value].max
                  end
                when Hash
                  max_action = access.keys.max

                  if max_action.present?
                    max_action = Permission::Action.from(max_action.serialize)

                    hash.merge!(resource => max_action) do |_, old_value, new_value|
                      [old_value, new_value].max
                    end
                  end
                end
              end
            end
          end.transform_values(&:to_sym)
        end

        sig { params(resource_type: ResourceType, name: String).returns(T.nilable(Integer)) }
        def granted_access_on_all_subjects(resource_type, name)
          get(resource_type).granted_access_on_all_subjects(name)&.serialize
        end

        sig do
          params(
            resource_type: ResourceType,
            name: String,
            subject_ids: T::Array[Integer]
          ).returns(PublicMethods::SubjectIdActionPairs)
        end
        def granted_subject_ids_with_actions_for(resource_type, name, subject_ids)
          get(resource_type).granted_subject_ids_with_actions_for(name, subject_ids)
        end

        sig { params(resource_type: ResourceType).returns(T::Array[String]) }
        def subject_types(resource_type)
          get(resource_type).permissions.keys
        end

        sig do
          params(
            resource_type: ResourceType,
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[Integer])
          ).void
        end
        def add_permissions_selection(resource_type:, permissions:, selection:)
          return unless permissions.present?

          resource_selection = get(resource_type)
          if requires_elevated_access?(resource_selection:, permissions:, selection:)
            resource_selection = promote_to_elevated_access(resource_selection:, permissions:, selection:)
          else
            resource_selection.add_permissions_selection(permissions:, selection:)
          end

          set(resource_type:, value: resource_selection)
        end

        sig do
          params(
            resource_type: ResourceType,
            selection: T.any(Selection, T::Array[Integer]),
            resource: String,
            action: T.any(Symbol, Permission::Action)
          ).returns(T::Boolean)
        end
        def explicitly_grants_permission?(resource_type:, selection:, resource:, action: :read)
          return false if resource_type.nil?

          action = Permission::Action.from(action) if action.is_a?(Symbol)
          action_value = action.serialize
          resource_selection = get(resource_type)

          case selection
          when Selection::All, Selection::Global, Selection::Parent
            action == resource_selection.granted_access_on_all_subjects(resource)
          when Array
            resource_selection
              .granted_subject_ids_with_actions_for(resource, selection)
              .any? { |_, granted_action| granted_action == action_value }
          else
            false
          end
        end

        sig do
          params(
            resource_selection: V2::ResourceSelection,
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[Integer])
          ).returns(T::Boolean)
        end
        def requires_elevated_access?(resource_selection:, permissions:, selection:)
          return false unless resource_selection.is_a?(V2::SelectionWithPermissions)
          return false unless selection.is_a?(Array)

          return false if resource_selection.selection == Selection::None
          return false if resource_selection.same_selection?(selection)

          true
        end

        sig do
          params(
            resource_selection: V2::ResourceSelection,
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[Integer])
          ).returns(V2::ElevatedAccessSelection)
        end
        def promote_to_elevated_access(resource_selection:, permissions:, selection:)
          elevated_access_selection = V2::ElevatedAccessSelection.default_value
          resource_selection = T.cast(resource_selection, V2::SelectionWithPermissions)

          case resource_selection.selection
          when Selection::All
            elevated_access_selection.selection = Selection::All
          when Array
            elevated_access_selection.selection = T.cast(resource_selection.selection, T::Array[Integer])
          end

          elevated_access_selection.permissions = resource_selection.permissions
          elevated_access_selection.add_permissions_selection(permissions:, selection:)

          elevated_access_selection
        end
      end
    end
  end
end
