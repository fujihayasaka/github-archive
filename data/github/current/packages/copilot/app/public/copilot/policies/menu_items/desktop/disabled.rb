# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Desktop
        class Disabled < Copilot::Policies::MenuItems::Desktop::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members won't have access to the feature"
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            desktop_disabled?
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
            elsif business?
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
