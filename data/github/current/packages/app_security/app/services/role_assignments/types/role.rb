# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class Role < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :octicon, String

      sig { params(role: ::Role).returns(Role) }
      def self.from_model(role)
        Role.new(
          id: role.id,
          name: role.display_name,
          description: role.description,
          octicon: role.octicon,
        )
      end
    end
  end
end
