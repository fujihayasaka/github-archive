# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Wire-shape struct for an owner entry in the v1 response.
      #
      # Per RFC github/copilot-ecosystem#934 §2, the v1 owner drops the legacy
      # `priority` field. With the GitHub-native allowlist as the enforcement
      # gate, all returned registries are equally valid for discovery and
      # order — not a numeric priority — encodes precedence on the wire.
      class RegistryOwner < T::Struct
        const :login, String
        const :id, Integer
        const :type, String
        const :name, String
        const :parent_login, T.nilable(String)
        const :parent_id, T.nilable(Integer)
        const :parent_name, T.nilable(String)

        # Explicit serializer. Avoids `T::Struct#serialize`, whose key/value
        # behavior on this public wire shape is more permissive than we want
        # (e.g. it serializes optional fields by omission rules controlled by
        # the runtime). Keys and ordering are stable by construction here.
        sig { returns(T::Hash[Symbol, T.anything]) }
        def to_h
          {
            # login is an attribute of the owner struct, not User#login
            # rubocop:disable GitHub/DoNotAllowLogin
            login: login,
            # rubocop:enable GitHub/DoNotAllowLogin
            id: id,
            type: type,
            name: name,
            parent_login: parent_login,
            parent_id: parent_id,
            parent_name: parent_name,
          }
        end

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          return false unless other.is_a?(RegistryOwner)
          # login is an attribute of the owner struct, not User#login
          # rubocop:disable GitHub/DoNotAllowLogin
          login == other.login && id == other.id && type == other.type &&
            name == other.name && parent_login == other.parent_login &&
            parent_id == other.parent_id && parent_name == other.parent_name
          # rubocop:enable GitHub/DoNotAllowLogin
        end
      end
    end
  end
end
