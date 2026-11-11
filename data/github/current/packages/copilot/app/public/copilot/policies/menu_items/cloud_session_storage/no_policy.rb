# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CloudSessionStorage
        class NoPolicy < Copilot::Policies::MenuItems::GeneralPolicies::Base
          sig { override.returns(String) }
          def label
            "Let organizations decide"
          end

          sig { override.returns(String) }
          def description
            "Organizations can set their own cloud session storage policy."
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
