# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class NoPolicy < Copilot::Policies::MenuItems::GeneralPolicies::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy."

          sig { override.returns(String) }
          def label
            "No policy"
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(T::Boolean) }
          def render?
            business? && !standalone_business?
          end
        end
      end
    end
  end
end
