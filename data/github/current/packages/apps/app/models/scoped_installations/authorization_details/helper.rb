# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class Helper

      sig do
        params(
          struct: ScopedInstallations::AuthorizationDetails::PublicMethods,
        ).returns(ScopedInstallations::AuthorizationDetails::Helper)
      end
      def self.with(struct)
        new(struct)
      end

      sig { params(struct: ScopedInstallations::AuthorizationDetails::PublicMethods).void }
      def initialize(struct)
        @struct = struct
      end

      sig { params(resource_type: ResourceType, resource: T.nilable(String), min_action: Symbol).returns(T::Boolean) }
      def has_minimum_action?(resource_type:, resource:, min_action:)
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Helper#has_minimum_action?", kind: :internal) do |_span|
          selection = @struct.selection_for(resource_type)
          return false if selection.none?

          if resource
            granted_action = @struct.all_permissions[resource]
            return false if granted_action.nil?

            Permission::Action.from(granted_action) >= Permission::Action.from(min_action)
          else
            subject_types = @struct.subject_types(resource_type)
            return false if subject_types.none?

            subject_types.any? { |r| has_minimum_action?(resource_type:, resource: r, min_action:) }
          end
        end
      end

    end
  end
end
