# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module McpRegistryAccess
        class AllowWithWarning < Copilot::Policies::MenuItems::McpRegistryAccess::Base
          sig { override.returns(String) }
          def value
            "allow_with_warning"
          end

          sig { override.returns(String) }
          def description
            "Members can use any remote or local MCP server, but see a warning before installing if it's not in the registry."
          end

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?
            mcp_registry_access_is?("allow_with_warning")
          end
        end
      end
    end
  end
end
