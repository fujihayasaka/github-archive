# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module MobileChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :mobile_chat_enabled?, :mobile_chat_disabled?, :no_mobile_chat_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_mobile_chat"
          end
        end
      end
    end
  end
end
