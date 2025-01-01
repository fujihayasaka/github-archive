# typed: strict
# frozen_string_literal: true

module Copilot
  module McpRegistry
    class Registry < T::Struct
      const :url, String
      const :registry_access, String
      const :owner, Copilot::McpRegistry::RegistryOwner

      sig { params(copilot_business: ::Copilot::Business, priority: Integer).returns(T.nilable(Copilot::McpRegistry::Registry)) }
      def self.for_business(copilot_business, priority)
        url = copilot_business.mcp_registry_url
        registry_access = copilot_business.mcp_registry_access

        return nil if url.nil?

        owner = RegistryOwner.new(
          login: copilot_business.display_login,
          id: copilot_business.id,
          type: "Business",
          parent_login: nil,
          parent_id: nil,
          priority: priority
        )

        Copilot::McpRegistry::Registry.new(
          url: url,
          registry_access: registry_access,
          owner: owner
        )
      end

      sig { params(copilot_organization: ::Copilot::Organization, priority: Integer).returns(T.nilable(Copilot::McpRegistry::Registry)) }
      def self.for_organization(copilot_organization, priority)
        parent = copilot_organization.business
        # orgs may get their mcp_registry_url from what is set on an owning enterprise so don't read directly from `mcp_allowlist` table
        url = copilot_organization.mcp_registry_url
        registry_access = copilot_organization.mcp_registry_access

        return nil if url.nil?

        owner = RegistryOwner.new(
          login: copilot_organization.display_login,
          id: copilot_organization.id,
          type: "Organization",
          parent_login: parent&.display_login,
          parent_id: parent&.id,
          priority: priority
        )

        Copilot::McpRegistry::Registry.new(
          url: url,
          registry_access: registry_access,
          owner: owner
        )
      end

      sig { params(other: Registry).returns(T::Boolean) }
      def ==(other)
        url == other.url && owner == other.owner
      end
    end
  end
end
