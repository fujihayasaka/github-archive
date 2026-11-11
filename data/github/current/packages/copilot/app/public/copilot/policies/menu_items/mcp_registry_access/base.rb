# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module McpRegistryAccess
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :mcp_registry_access_is?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "mcp_registry_access"
          end
        end
      end
    end
  end
end
