# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Wire-shape struct for a single registry entry in the v1 response.
      #
      # Per RFC github/copilot-ecosystem#934 §2, the v1 shape drops
      # `registry_access` (enforcement is no longer a per-registry property
      # once the GitHub-native allowlist is the gate). `capabilities` is
      # preserved as an additive field shared with the legacy shape.
      #
      # `priority` is intentionally absent on the owner — see
      # `Copilot::Mcp::V1::RegistryOwner`.
      class Registry < T::Struct
        const :url, String
        const :owner, Copilot::Mcp::V1::RegistryOwner
        const :capabilities, T.nilable(Copilot::Mcp::RegistryCapabilities), default: nil

        # Custom serialization. Mirrors `Copilot::Mcp::Registry#to_h` in
        # omitting `capabilities` when nil so clients that integrated against
        # the pre-capabilities shape see no extra field.
        sig { returns(T::Hash[Symbol, T.anything]) }
        def to_h
          result = T.let({
            url: url,
            owner: owner.to_h,
          }, T::Hash[Symbol, T.anything])
          result[:capabilities] = capabilities.to_h if capabilities
          result
        end

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          return false unless other.is_a?(Registry)
          url == other.url &&
            owner == other.owner &&
            capabilities == other.capabilities
        end
      end
    end
  end
end
