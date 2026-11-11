# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CloudSessionStorage
        class ViewFromCloud < Copilot::Policies::MenuItems::GeneralPolicies::Base
          sig { override.returns(String) }
          def label
            "View from cloud"
          end

          sig { override.returns(String) }
          def description
            if standalone_business?
              "Sessions are stored in the cloud and can be viewed on github.com."
            elsif business?
              "Sessions are stored in the cloud and can be viewed on github.com for all organizations."
            elsif organization?
              "Sessions are stored in the cloud and can be viewed on github.com for members of this organization."
            else
              ""
            end
          end

          sig { override.returns(String) }
          def self.value
            "view_from_cloud"
          end
        end
      end
    end
  end
end
