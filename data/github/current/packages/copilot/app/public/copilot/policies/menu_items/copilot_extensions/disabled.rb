# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotExtensions
        class Disabled < Copilot::Policies::MenuItems::CopilotExtensions::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            copilot_extensions_disabled?
          end

          sig { override.returns(String) }
          def description
            if business?
              BUSINESS_DESCRIPTION
            else
              ORGANIZATION_DESCRIPTION
            end
          end
        end
      end
    end
  end
end
