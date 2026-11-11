# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class RoleAssignment < T::Struct
      const :role, Role
      const :directly_assigned, T::Boolean
      const :indirect_assignments, T::Array[IndirectAssignmentSource], default: []
      const :org_access, T.nilable(OrgAccess)

      # Define serialization for React payload
      sig { params(options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def as_json(options = {})
        json = {
          role: role.as_json,
          directly_assigned:,
          indirect_assignments:,
        }

        json[:org_access] = org_access.as_json if org_access

        json
      end
    end
  end
end
