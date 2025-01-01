# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module McpRegistryAccess
        class AllowAll < Copilot::Policies::MenuItems::McpRegistryAccess::Base
          sig { override.returns(String) }
          def value
            "allow_all"
          end

          sig { override.returns(String) }
          def description
            "Members with Copilot seats assigned can use any remote or local MCP server, even if it's not in the uploaded registry."
          end

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?
            mcp_registry_access_is?("allow_all")
          end
        end
      end
    end
  end
end
