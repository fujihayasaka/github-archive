# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      module McpRegistries
        extend T::Helpers
        include Copilot::Organizations::Signatures
        include GitHub::Memoizer

        abstract!

        sig { override.returns(T.nilable(String)) }
        def mcp_registry_url
          # When the enterprise has an explicit policy (i.e., not "Let organizations decide"),
          # always use the enterprise's registry URL.
          if copilot_business && !T.must(copilot_business).mcp_no_policy?
            return copilot_business&.mcp_registry_url
          end
          # When the enterprise has explicitly delegated to orgs ("Let organizations
          # decide" == mcp_no_policy), prefer the org's own registry if present;
          # otherwise fall back to the enterprise's configured registry so the org
          # inherits the enterprise-level GitHub MCP Registry.
          mcp_registry&.allowlist_url || copilot_business&.mcp_registry_url
        end

        sig { override.returns(T.nilable(Integer)) }
        def mcp_registry_id
          # The mcp_registry_id is only available when the enterprise has delegated
          # registry management to orgs ("Let organizations decide" == mcp_no_policy).
          # When the enterprise has an explicit policy, this returns nil.
          return nil if copilot_business && !T.must(copilot_business).mcp_no_policy?
          mcp_registry&.id
        end

        sig { override.params(access_type: T.any(String, Symbol)).returns(T::Boolean) }
        def mcp_registry_access_is?(access_type)
          if copilot_business && !T.must(copilot_business).mcp_no_policy?
            return T.must(copilot_business).mcp_registry_access_is?(access_type)
          end

          # Mirror the fallback logic in #mcp_registry_url: when the effective
          # registry URL comes from the enterprise (because the org has no usable
          # registry of its own), defer to the enterprise's access setting so the
          # URL and access values stay consistent.
          if inherits_business_registry?
            return T.must(copilot_business).mcp_registry_access_is?(access_type)
          end

          case access_type.to_s
          when "allow_all" # Default option
            mcp_registry.nil? || T.must(mcp_registry).registry_access_allow_all?
          when "registry_only"
            !!mcp_registry&.registry_access_registry_only?
          else
            Kernel.raise ArgumentError, "Unknown access type: #{access_type}"
          end
        end

        sig { returns(String) }
        def mcp_registry_access
          if copilot_business && !copilot_business&.mcp_no_policy?
            return T.must(copilot_business).mcp_registry_access
          end
          # When falling back to the enterprise's registry URL (see #mcp_registry_url),
          # also inherit the enterprise's registry access setting.
          if inherits_business_registry?
            return T.must(copilot_business).mcp_registry_access
          end
          mcp_registry&.registry_access || "allow_all"
        end

        sig { override.returns(T.nilable(Copilot::McpRegistry)) }
        def mcp_registry
          ::Copilot::McpRegistry.for_organization(organization_object).first
        end

        # True when the org's effective MCP registry URL comes from the parent
        # business because the org has no usable registry URL of its own. This is
        # the condition under which the org should also inherit the business'
        # access setting, keeping URL and access consistent.
        sig { returns(T::Boolean) }
        private def inherits_business_registry?
          return false unless copilot_business&.mcp_registry_url
          mcp_registry&.allowlist_url.blank?
        end
      end
    end
  end
end
