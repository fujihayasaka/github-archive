# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CloudSessionStorage
        class ViewAndControl < Copilot::Policies::MenuItems::GeneralPolicies::Base
          sig { override.returns(String) }
          def label
            "View and control from cloud"
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              "Sessions are stored in the cloud and can be viewed and steered on github.com."
            elsif business?
              "Sessions are stored in the cloud and can be viewed and steered on github.com for all organizations."
            elsif organization?
              "Sessions are stored in the cloud and can be viewed and steered on github.com for members of this organization."
            else
              ""
            end
          end

          sig { override.returns(String) }
          def self.value
            "view_and_control"
          end
        end
      end
    end
  end
end
