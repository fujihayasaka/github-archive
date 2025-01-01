# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::AccessorsDependency
        extend T::Sig
        extend T::Helpers

        requires_ancestor { V2 }

        DEFAULT_RESOURCE_SELECTION_BY_PROPERTY = T.let({
          codespace: V2::SelectionWithPermissions,
          organization: V2::SelectionWithPermissions,
          package: V2::SubjectIdsOnlySelection,
          pull_request: V2::SubjectIdsOnlySelection,
          workflow_run: V2::SubjectIdsOnlySelection,
          repository: V2::SelectionWithPermissions,
        }, T::Hash[Symbol, V2::ResourceSelectionDefaultable])

        sig { params(resource_type: ResourceType).returns(V2::ResourceSelection) }
        def get(resource_type)
          name = resource_type.serialize.to_sym

          if properties.include?(name)
            property = self.public_send(name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            return property if property.present?
          end

          resource_selection_class = T.must(DEFAULT_RESOURCE_SELECTION_BY_PROPERTY[name])
          resource_selection_class.default_value
        end

        sig do
          params(
            resource_type: ResourceType,
            value: V2::ResourceSelection
          ).returns(T.nilable(V2::ResourceSelection))
        end
        def set(resource_type:, value:)
          name = resource_type.serialize.to_sym
          return unless properties.include?(name)

          instance_variable_set(:"@#{name}", value)
        end

        sig { params(resource_type: ResourceType).returns(Selection) }
        def selection_for(resource_type)
          selection = get(resource_type).selection

          case selection
          when Array
            Selection::Subset
          else
            selection
          end
        end
      end
    end
  end
end
