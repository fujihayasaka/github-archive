# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CloudSessionStorage
        class Disabled < Copilot::Policies::MenuItems::GeneralPolicies::Base
          sig { override.returns(String) }
          def label
            "No cloud access"
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              "Sessions are not stored in the cloud. Remote viewing and control are disabled."
            elsif business?
              "Sessions are not stored in the cloud for any organization. It cannot be enabled at the organization level."
            elsif organization?
              "Sessions are not stored in the cloud for members of this organization."
            else
              ""
            end
          end
        end
      end
    end
  end
end
