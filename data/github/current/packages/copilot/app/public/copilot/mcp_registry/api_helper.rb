# typed: strict
# frozen_string_literal: true

module Copilot
  module McpRegistry
    module ApiHelper
      MOCK_MCP_REGISTRY = T.let([
          {
            url: "https://mcp.azure.com/",
            registry_access: "allow_all",
            owner: {
              login: "github",
              id: 1,
              type: "Business",
              parent_login: nil,
              parent_id: nil,
              priority: 1
            }
          },
          {
            url: "https://burger-mcp-registry.com",
            registry_access: "allow_with_warning",
            owner: {
              login: "bobs-burgers",
              id: 3097,
              type: "Organization",
              parent_login: "github-inc",
              parent_id: 2,
              priority: 2
            }
          },
          {
            url: "https://copilot-mcp-registry.github.com",
            registry_access: "registry_only",
            owner: {
              login: "standalone-org",
              id: 507,
              type: "Organization",
              parent_login: nil,
              parent_id: nil,
              priority: 3
            }
          }
        ].freeze, T::Array[T::Hash[Symbol, T.any(String, Integer, T::Hash[Symbol, T.any(String, Integer)])]])

      sig { params(copilot_user: ::Copilot::User).returns(T::Array[Copilot::McpRegistry::Registry]) }
      def get_mcp_registries(copilot_user)
        priority = 1
        entities = get_viable_entities(copilot_user)
        sorted_entities = sort_registry_entities(entities)
        registries = sorted_entities.map do |entity|
          if entity.sorbet_class == ::Business
            registry = Copilot::McpRegistry::Registry.for_business(T.cast(entity, ::Copilot::Business), priority)
          else
            registry = Copilot::McpRegistry::Registry.for_organization(T.cast(entity, ::Copilot::Organization), priority)
          end
          priority += 1 if registry.present?

          registry
        end
        only_registries = registries.compact

        only_registries.blank? ? [] : [only_registries.first]
      end

      sig { params(registry_access: String).returns(Integer) }
      def registry_access_priority(registry_access)
        case registry_access
        when "registry_only"
          0
        when "allow_with_warning"
          1
        when "allow_all"
          2
        else
          3
        end
      end

      # Sort entities for MCP registries
      # Sort order:
      # - Scope priority: Enterprise > Organization
      # - Enforcement priority: Registry only > Allow with warning > Allow all
      # - Tie-breaker: last_updated (desc)
      # - Final tie-breaker: entity primary key/ID (asc)
      sig { params(entities: T::Array[T.any(Copilot::Business, Copilot::Organization)]).returns(T::Array[T.any(Copilot::Business, Copilot::Organization)]) }
      def sort_registry_entities(entities)
        entities.sort do |entity_a, entity_b|
          a_type = entity_a.sorbet_class == ::Business ? 0 : 1
          b_type = entity_b.sorbet_class == ::Business ? 0 : 1
          type_comparison = a_type <=> b_type
          next type_comparison unless type_comparison.zero?

          a_registry_access = registry_access_priority(entity_a.mcp_registry_access)
          b_registry_access = registry_access_priority(entity_b.mcp_registry_access)
          registry_access_comparison = a_registry_access <=> b_registry_access
          next registry_access_comparison unless registry_access_comparison.zero?

          a_registry_last_updated = entity_a.mcp_registry&.updated_at || Time.at(0)
          b_registry_last_updated = entity_b.mcp_registry&.updated_at || Time.at(0)
          # last updated to be sorted in descending order
          last_updated_comparison = b_registry_last_updated <=> a_registry_last_updated
          next last_updated_comparison unless last_updated_comparison.zero?

          entity_a.id <=> entity_b.id
        end
      end

      # return a list of viable entities to get mcp registries
      # a viable entity is an Enterprise or Organization where:
      #  - mcp policy is enabled
      #  - Organization only: If it is an enterprise owned organization where the enterprise has the mcp policy set to no policy, or it is a standalone organization
      #    (This is to prevent duplicate registries being returned when an org inherits its mcp policy/registry from its owning enterprise)
      sig { params(copilot_user: ::Copilot::User).returns(T::Array[T.any(Copilot::Business, Copilot::Organization)]) }
      def get_viable_entities(copilot_user)
        viable_copilot_businesses = copilot_user.copilot_businesses_all.select(&:mcp_enabled?)
        business_ids = viable_copilot_businesses.map(&:id)
        viable_orgs = copilot_user.copilot_organizations_including_trials.select do |org|
          org.mcp_enabled? && (org.business.nil? || business_ids.exclude?(org.business&.id))
        end

        viable_copilot_businesses + viable_orgs
      end
    end
  end
end
