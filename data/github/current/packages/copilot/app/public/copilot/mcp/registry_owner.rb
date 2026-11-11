# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    class RegistryOwner < T::Struct
      const :login, String
      const :id, Integer
      const :type, String
      const :name, String
      const :parent_login, T.nilable(String)
      const :parent_id, T.nilable(Integer)
      const :parent_name, T.nilable(String)
      const :priority, Integer

      sig { params(other: RegistryOwner).returns(T::Boolean) }
      def ==(other)
        # login is an attribute of the owner
        # rubocop:disable GitHub/DoNotAllowLogin
        login == other.login && id == other.id && type == other.type && name == other.name &&
          parent_login == other.parent_login && parent_id == other.parent_id &&
          parent_name == other.parent_name && priority == other.priority
      end
    end
  end
end
