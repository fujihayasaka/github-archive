# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    class Registry < T::Struct
      const :url, String
      const :registry_access, String
      const :owner, Copilot::Mcp::RegistryOwner
      const :capabilities, T.nilable(Copilot::Mcp::RegistryCapabilities), default: nil

      sig { params(copilot_business: ::Copilot::Business, priority: Integer, capabilities: T.nilable(Copilot::Mcp::RegistryCapabilities)).returns(T.nilable(Copilot::Mcp::Registry)) }
      def self.for_business(copilot_business, priority:, capabilities: nil)
        url = copilot_business.mcp_registry_url
        registry_access = copilot_business.mcp_registry_access

        # When no URL is configured but registry_access is allow_all, return
        # a registry entry with an empty URL to indicate that all registries are allowed.
        # Handle both nil and empty string URLs.
        if url.blank?
          return nil unless registry_access == "allow_all"
          url = ""
        end

        registry_access = "registry_only" if url == Copilot::McpRegistry::GITHUB_ENTERPRISE_URL

        owner = RegistryOwner.new(
          login: copilot_business.display_login,
          id: copilot_business.id,
          type: "Business",
          name: copilot_business.safe_profile_name,
          parent_login: nil,
          parent_id: nil,
          parent_name: nil,
          priority: priority
        )

        Copilot::Mcp::Registry.new(
          url: url,
          registry_access: registry_access,
          owner: owner,
          capabilities: capabilities
        )
      end

      sig { params(copilot_organization: ::Copilot::Organization, priority: Integer, capabilities: T.nilable(Copilot::Mcp::RegistryCapabilities)).returns(T.nilable(Copilot::Mcp::Registry)) }
      def self.for_organization(copilot_organization, priority:, capabilities: nil)
        parent = copilot_organization.business
        # orgs may get their mcp_registry_url from what is set on an owning enterprise so don't read directly from `mcp_allowlist` table
        url = copilot_organization.mcp_registry_url
        registry_access = copilot_organization.mcp_registry_access

        if url.blank?
          return nil unless registry_access == "allow_all"
          url = ""
        end

        registry_access = "registry_only" if url == Copilot::McpRegistry::GITHUB_ENTERPRISE_URL

        owner = RegistryOwner.new(
          login: copilot_organization.display_login,
          id: copilot_organization.id,
          type: "Organization",
          name: copilot_organization.safe_profile_name,
          parent_login: parent&.display_login,
          parent_id: parent&.id,
          parent_name: parent&.safe_profile_name,
          priority: priority
        )

        Copilot::Mcp::Registry.new(
          url: url,
          registry_access: registry_access,
          owner: owner,
          capabilities: capabilities
        )
      end

      # Custom serialization that omits capabilities when nil, ensuring backward
      # compatibility with clients that do not expect the field.
      sig { returns(T::Hash[Symbol, T.anything]) }
      def to_h
        result = {
          url: url,
          registry_access: registry_access,
          owner: owner.serialize,
        }
        result[:capabilities] = capabilities.to_h if capabilities
        result
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Registry)

        url == other.url &&
          registry_access == other.registry_access &&
          owner == other.owner &&
          capabilities == other.capabilities
      end
    end
  end
end
