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
          if copilot_business && !T.must(copilot_business).mcp_no_policy?
            return copilot_business&.mcp_registry_url
          end
          mcp_registry&.allowlist_url
        end

        sig { override.returns(T.nilable(Integer)) }
        def mcp_registry_id
          return nil if copilot_business && !T.must(copilot_business).mcp_no_policy?
          mcp_registry&.id
        end

        sig { params(access_type: T.any(String, Symbol)).returns(T::Boolean) }
        def mcp_registry_access_is?(access_type)
          if copilot_business && !T.must(copilot_business).mcp_no_policy?
            return T.must(copilot_business).mcp_registry_access_is?(access_type)
          end

          case access_type.to_s
          when "allow_all" # Default option
            mcp_registry.nil? || T.must(mcp_registry).registry_access_allow_all?
          when "allow_with_warning"
            !!mcp_registry&.registry_access_allow_with_warning?
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
          mcp_registry&.registry_access || "allow_all"
        end

        sig { override.returns(T.nilable(Copilot::McpAllowlist)) }
        memoize def mcp_registry
          ::Copilot::McpAllowlist.for_organization(organization_object).first
        end
      end
    end
  end
end
