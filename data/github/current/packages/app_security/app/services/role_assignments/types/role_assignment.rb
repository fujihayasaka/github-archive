# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class RoleAssignment < T::Struct
      const :role, Role
      const :directly_assigned, T::Boolean
      const :indirect_assignments, T::Array[IndirectAssignmentSource], default: []
    end
  end
end
