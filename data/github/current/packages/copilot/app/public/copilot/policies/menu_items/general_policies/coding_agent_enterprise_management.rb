# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class CodingAgentEnterpriseManagement < Copilot::Policies::MenuItems::GeneralPolicies::Base
          sig { override.returns(String) }
          def label
            "Enable for selected organizations"
          end

          sig { override.returns(String) }
          def description
            "Enable or disable access for individual organizations."
          end

          sig { override.returns(T::Boolean) }
          def render?
            !!(business? && !standalone_business?)
          end
        end
      end
    end
  end
end
