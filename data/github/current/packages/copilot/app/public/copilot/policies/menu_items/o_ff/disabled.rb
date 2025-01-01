# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module OFf
        class Disabled < Copilot::Policies::MenuItems::OFf::Base
          STANDALONE_BUSINESS_DESCRIPTION = "Members won’t have access to the feature"
          BUSINESS_DESCRIPTION = "All organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"
          USER_DESCRIPTION = "You won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            o_ff_disabled?
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              STANDALONE_BUSINESS_DESCRIPTION
            elsif business?
              BUSINESS_DESCRIPTION
            elsif organization?
              ORGANIZATION_DESCRIPTION
            elsif user?
              USER_DESCRIPTION
            else
              ORGANIZATION_DESCRIPTION
            end
          end
        end
      end
    end
  end
end
