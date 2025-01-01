# typed: strict
# frozen_string_literal: true

module Copilot
  module McpRegistry
    class RegistryOwner < T::Struct
      const :login, String
      const :id, Integer
      const :type, String
      const :parent_login, T.nilable(String)
      const :parent_id, T.nilable(Integer)
      const :priority, Integer

      sig { params(other: RegistryOwner).returns(T::Boolean) }
      def ==(other)
        # login is an attribute of the owner
        # rubocop:disable GitHub/DoNotAllowLogin
        login == other.login && id == other.id && type == other.type &&
          parent_login == other.parent_login && parent_id == other.parent_id && priority == other.priority
      end
    end
  end
end
