# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module McpRegistryAccess
        class RegistryOnly < Copilot::Policies::MenuItems::McpRegistryAccess::Base
          sig { override.returns(String) }
          def value
            "registry_only"
          end

          sig { override.returns(String) }
          def description
            "Members can only use remote and local MCP servers listed in the registry. All others are blocked."
          end

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?
            mcp_registry_access_is?("registry_only")
          end
        end
      end
    end
  end
end
