# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class NoPolicy < Copilot::Policies::MenuItems::GeneralPolicies::Base
          DESCRIPTION = "Organizations can set their own policy."

          sig { override.returns(String) }
          def label
            "Let organizations decide"
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
