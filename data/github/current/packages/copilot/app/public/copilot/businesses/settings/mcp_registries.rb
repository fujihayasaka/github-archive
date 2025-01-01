# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Settings
      module McpRegistries
        extend T::Helpers
        include Copilot::Businesses::Signatures
        include GitHub::Memoizer

        abstract!

        sig { override.returns(T.nilable(String)) }
        def mcp_registry_url
          mcp_registry&.allowlist_url
        end

        sig { returns(String) }
        def mcp_registry_access
          mcp_registry&.registry_access || "allow_all"
        end

        sig { params(access_type: T.any(String, Symbol)).returns(T::Boolean) }
        def mcp_registry_access_is?(access_type)
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

        sig { override.returns(T.nilable(Copilot::McpAllowlist)) }
        memoize def mcp_registry
          ::Copilot::McpAllowlist.for_business(business_object).first
        end
      end
    end
  end
end
