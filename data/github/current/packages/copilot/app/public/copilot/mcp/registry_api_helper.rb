# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module RegistryApiHelper
      class ViableEntitiesResult < T::Struct
        const :entities, T::Array[T.any(Copilot::Business, Copilot::Organization)]
        const :strictness_override_org_ids, T::Set[Integer]
      end

      # When `for_v1:` is true, the helper produces the registry list for the
      # `GET /copilot/mcp_registry/v1` endpoint as defined in RFC
      # github/copilot-ecosystem#934. Concretely that changes three things
      # relative to the legacy path:
      #
      #   * Strictness override is disabled. The legacy endpoint replaces an
      #     enterprise registry with a child org's own registry when the org
      #     is stricter than its enterprise; v1 has no `registry_access` field
      #     on the wire and treats enforcement as an allowlist concern, so the
      #     override is meaningless and we always return the enterprise's
      #     registry for enterprise-owned orgs.
      #   * "Most restrictive wins" is disabled. The legacy endpoint drops
      #     `allow_all` registries when any `registry_only` registry is
      #     present; v1 returns the full 0..N list as discovery data and lets
      #     the GitHub-native allowlist enforce.
      #   * Ordering drops the `registry_access` tier. v1 ordering is
      #     scope (Enterprise > Organization) → recency desc → id asc, since
      #     `registry_access` is no longer part of the response shape.
      sig { params(copilot_user: ::Copilot::User, repo_nwo: T.nilable(String), exclude_github_enterprise_registry: T::Boolean, for_v1: T::Boolean).returns(T::Array[Copilot::Mcp::Registry]) }
      def get_mcp_registries(copilot_user, repo_nwo: nil, exclude_github_enterprise_registry: false, for_v1: false)
        include_capabilities = copilot_user.feature_flag_enabled_include_parents?(:copilot_mcp_registry_capabilities, default: false)
        viable_result = get_viable_entities(copilot_user, apply_strictness_override: !for_v1)
        sorted_entities = if for_v1
          sort_registry_entities_v1(viable_result.entities)
        else
          sort_registry_entities(viable_result.entities)
        end

        priority = 1
        registries = sorted_entities.map do |entity|
          if entity.sorbet_class == ::Business
            url = entity.mcp_registry_url
            capabilities = include_capabilities ? capabilities_for_url(url) : nil
            registry = Copilot::Mcp::Registry.for_business(T.cast(entity, ::Copilot::Business), priority: priority, capabilities: capabilities)
          elsif viable_result.strictness_override_org_ids.include?(entity.id)
            # This org was included because its own policy is stricter than its parent enterprise.
            # Build the registry from the org's own mcp_registry, not the enterprise-delegated one.
            org = T.cast(entity, ::Copilot::Organization)
            own_registry = org.mcp_registry
            url = own_registry&.allowlist_url
            capabilities = include_capabilities ? capabilities_for_url(url) : nil
            registry = build_registry_from_own_data(org, own_registry: own_registry, priority: priority, capabilities: capabilities)
          else
            org = T.cast(entity, ::Copilot::Organization)
            url = org.mcp_registry_url
            capabilities = include_capabilities ? capabilities_for_url(url) : nil
            registry = Copilot::Mcp::Registry.for_organization(org, priority: priority, capabilities: capabilities)
          end
          priority += 1 if registry.present?

          registry
        end
        only_registries = registries.compact

        # Drop registries backed by the GitHub Enterprise MCP Registry when the
        # caller cannot use them. URL-only legacy clients consume `data.mcp_registries[0].url`
        # without providing a user-bound dotcom token or repo context, so they
        # cannot authenticate against the GitHub-native registry. Filtering here
        # keys eligibility on the registry's source (its URL), not on user-agent
        # or other client-side signals.
        if exclude_github_enterprise_registry
          only_registries = only_registries.reject { |r| r.url == Copilot::McpRegistry::GITHUB_ENTERPRISE_URL }
        end

        # If any registry enforces "registry_only", drop all "allow_all" registries.
        # The stricter policy wins across unrelated memberships. v1 disables
        # this collapse — the full 0..N set is returned for discovery and the
        # allowlist (not the response shape) enforces.
        if !for_v1 && only_registries.any? { |r| r.registry_access == "registry_only" }
          only_registries = only_registries.select { |r| r.registry_access == "registry_only" }
        end

        # In v1 the response shape drops `registry_access`, so the legacy
        # `allow_all` placeholder registry (a Registry with `url: ""` returned
        # when an eligible entity has no configured allowlist URL) loses the
        # signal that distinguishes "allow all / no registry" from a real
        # registry entry. Drop those placeholders here so clients see an empty
        # `mcp_registries` list instead of a blank-URL entry.
        only_registries = only_registries.reject { |r| r.url.blank? } if for_v1

        # When a repo NWO is provided, filter registries to only those applicable
        # to the repo's owner. Matches by:
        # 1. Direct owner.login match (org or enterprise owns the repo directly)
        # 2. owner.parent_login match (child org's registry, enterprise login is the repo owner)
        # 3. Enterprise registry covers a child org that matches the repo owner
        if repo_nwo.present?
          owner_login, _ = repo_nwo.split("/", 2)
          owner_login_downcase = T.must(owner_login).downcase

          # Build a set of enterprise IDs whose child orgs match the repo owner.
          # This handles: enterprise registry returned, repo owned by child org of that enterprise.
          matching_enterprise_ids = copilot_user.copilot_organizations
            .select { |org| org.display_login.downcase == owner_login_downcase && org.business.present? }
            .map { |org| T.must(org.business).id }
            .to_set

          only_registries = only_registries.select do |registry|
            # login is an attribute of the owner struct, not User#login
            # rubocop:disable GitHub/DoNotAllowLogin
            registry.owner.login.downcase == owner_login_downcase ||
              registry.owner.parent_login&.downcase == owner_login_downcase ||
              (registry.owner.type == ::Business.name && matching_enterprise_ids.include?(registry.owner.id))
            # rubocop:enable GitHub/DoNotAllowLogin
          end
        end

        only_registries
      end

      sig { params(registry_access: String).returns(Integer) }
      def registry_access_priority(registry_access)
        case registry_access
        when "registry_only"
          0
        when "allow_all"
          1
        else
          2
        end
      end

      # Sort entities for MCP registries
      # Sort order:
      # - Scope priority: Enterprise > Organization
      # - Enforcement priority: Registry only > Allow all
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

      # v1 sort: identical to `sort_registry_entities` except the
      # `registry_access` tier is removed. Per RFC
      # github/copilot-ecosystem#934, v1 has no `registry_access` field on the
      # wire, so ordering by it would be invisible to clients and surprising.
      # Order: scope (Enterprise > Organization) → recency desc → id asc.
      sig { params(entities: T::Array[T.any(Copilot::Business, Copilot::Organization)]).returns(T::Array[T.any(Copilot::Business, Copilot::Organization)]) }
      def sort_registry_entities_v1(entities)
        entities.sort do |entity_a, entity_b|
          a_type = entity_a.sorbet_class == ::Business ? 0 : 1
          b_type = entity_b.sorbet_class == ::Business ? 0 : 1
          type_comparison = a_type <=> b_type
          next type_comparison unless type_comparison.zero?

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
      #  - Organization only: If it is an enterprise owned organization, it is included only when:
      #    - The owning enterprise does not have mcp policy enabled (no policy / disabled), OR
      #    - The org's own registry_access is stricter than the enterprise's (registry_only vs allow_all)
      #  - Standalone organizations (no enterprise or enterprise has no mcp policy) are always included
      #  When a child org is included because it is stricter, the parent enterprise is excluded
      #  to avoid returning both.
      sig { params(copilot_user: ::Copilot::User, apply_strictness_override: T::Boolean).returns(ViableEntitiesResult) }
      def get_viable_entities(copilot_user, apply_strictness_override: true)
        viable_copilot_businesses = copilot_user.copilot_businesses_all.select(&:mcp_enabled?)
        business_ids = viable_copilot_businesses.map(&:id)

        # Track enterprises that should be excluded because a stricter child org overrides them
        excluded_business_ids = T.let(Set.new, T::Set[Integer])
        # Track orgs that were included because they are stricter than their parent enterprise
        strictness_override_org_ids = T.let(Set.new, T::Set[Integer])

        viable_orgs = copilot_user.copilot_organizations.select do |org|
          next false unless org.mcp_enabled?

          parent_business_id = org.business&.id
          # Standalone org or enterprise not in viable businesses → include
          if parent_business_id.nil? || business_ids.exclude?(parent_business_id)
            next true
          end

          # Enterprise-owned org where enterprise has MCP enabled.
          # The v1 endpoint disables the strictness override entirely because
          # the override exists only to surface a stricter `registry_access`
          # value, and v1 does not expose `registry_access` on the wire.
          next false unless apply_strictness_override

          # Include if the org's own access is stricter than the enterprise's.
          org_own_access = org.mcp_registry&.registry_access
          next false if org_own_access.nil?

          found_business = viable_copilot_businesses.find { |b| b.id == parent_business_id }
          next false unless found_business

          enterprise_access = found_business.mcp_registry_access

          if org_own_access == "registry_only" && enterprise_access != "registry_only"
            # Only override if the org actually has a registry URL to serve
            next false if org.mcp_registry&.allowlist_url.nil?
            # Child org is stricter → include org, exclude enterprise
            excluded_business_ids.add(parent_business_id)
            strictness_override_org_ids.add(org.id)
            next true
          end

          false
        end

        included_businesses = viable_copilot_businesses.reject { |b| excluded_business_ids.include?(b.id) }
        ViableEntitiesResult.new(
          entities: included_businesses + viable_orgs,
          strictness_override_org_ids: strictness_override_org_ids
        )
      end

      # Build a registry from the org's own mcp_registry record, bypassing enterprise delegation.
      # Used when a child org's own policy is stricter than its parent enterprise.
      sig { params(copilot_organization: ::Copilot::Organization, priority: Integer, own_registry: T.nilable(::Copilot::McpRegistry), capabilities: T.nilable(Copilot::Mcp::RegistryCapabilities)).returns(T.nilable(Copilot::Mcp::Registry)) }
      def build_registry_from_own_data(copilot_organization, priority:, own_registry: nil, capabilities: nil)
        own_registry ||= copilot_organization.mcp_registry
        return nil if own_registry.nil?

        url = own_registry.allowlist_url
        return nil if url.nil?

        registry_access = own_registry.registry_access
        registry_access = "registry_only" if url == Copilot::McpRegistry::GITHUB_ENTERPRISE_URL

        parent = copilot_organization.business
        owner = Copilot::Mcp::RegistryOwner.new(
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

      # Returns capabilities for a registry URL, or nil if the URL
      # uses the standard external contract.
      sig { params(url: T.nilable(String)).returns(T.nilable(Copilot::Mcp::RegistryCapabilities)) }
      def capabilities_for_url(url)
        return nil if url.nil?
        return nil unless url == Copilot::McpRegistry::GITHUB_ENTERPRISE_URL

        Copilot::Mcp::RegistryCapabilities::GITHUB_ENTERPRISE_CAPABILITIES
      end
    end
  end
end
