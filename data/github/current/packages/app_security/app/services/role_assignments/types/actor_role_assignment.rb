# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class ActorRoleAssignment < T::Struct
      const :actor, Actor
      const :role_assignments, T::Array[RoleAssignment]
    end
  end
end
