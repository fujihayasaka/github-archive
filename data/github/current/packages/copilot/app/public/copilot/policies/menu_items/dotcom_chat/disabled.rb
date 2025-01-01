# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module DotcomChat
        class Disabled < Copilot::Policies::MenuItems::DotcomChat::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"
          ORGANIZATION_DESCRIPTION = "Members of this organization won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            if business?
              dotcom_chat_disabled?
            else
              dotcom_chat_disabled? || dotcom_chat_no_policy? || (!dotcom_chat_enabled? && !dotcom_chat_disabled?)
            end
          end

          sig { override.returns(String) }
          def description
            business? ? BUSINESS_DESCRIPTION : ORGANIZATION_DESCRIPTION
          end
        end
      end
    end
  end
end
