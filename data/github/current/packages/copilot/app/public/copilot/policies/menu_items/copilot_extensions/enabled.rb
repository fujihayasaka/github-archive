# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotExtensions
        class Enabled < Copilot::Policies::MenuItems::CopilotExtensions::Base
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members with a Copilot license will have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            copilot_extensions_enabled?
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
