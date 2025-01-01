# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class Helper
      extend T::Sig

      sig do
        params(
          struct: ScopedInstallations::AuthorizationDetails::Structs::V1,
        ).returns(ScopedInstallations::AuthorizationDetails::Helper)
      end
      def self.with(struct)
        new(struct)
      end

      sig { params(struct: ScopedInstallations::AuthorizationDetails::Structs::V1).void }
      def initialize(struct)
        @struct = struct
      end

      sig { params(type: ResourceType, resource: T.nilable(String), min_action: Symbol).returns(T::Boolean) }
      def has_minimum_action?(type:, resource:, min_action:)
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Helper#has_minimum_action?", kind: :internal) do |_span|
          selection = @struct.selection_for(type)

          return false if selection.none?
          return false if @struct.subject_types_and_actions_for(type).none?

          permissions = @struct.subject_types_and_actions_for(type)

          if resource
            granted_action = permissions[resource]
            return false if granted_action.nil?

            granted_action >= Permission::Action.from(min_action)
          else
            permissions.any? { |r, _| has_minimum_action?(type:, resource: r, min_action:) }
          end
        end
      end

      sig { params(type: ResourceType, resource: T.nilable(String), min_action: Symbol).returns(T::Array[Integer]) }
      def asymmetric_subject_ids_for(type:, resource:, min_action:)
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Helper#asymmetric_subject_ids_for", kind: :internal) do |_span|
          if resource
            granted_access = @struct.asymmetric_for(type)[resource]
            return [] if granted_access.nil?

            # Collect all of the subject ids that greater than or equal to the
            # minimum action.
            granted_access.to_a.flat_map do |action, subject_ids|
              Permission::Action.from(action) >= Permission::Action.from(min_action) ? subject_ids : []
            end.uniq
          else
            # Iterate through all of the granted resources and collect the
            # subject ids.
            @struct.asymmetric_for(type).keys.flat_map do |resource|
              asymmetric_subject_ids_for(type:, resource: resource, min_action:)
            end.uniq
          end
        end
      end
    end
  end
end
