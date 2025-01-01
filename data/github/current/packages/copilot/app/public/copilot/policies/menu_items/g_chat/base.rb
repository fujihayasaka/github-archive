# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :g_chat_enabled?, :g_chat_disabled?, :g_chat_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_g_chat"
          end
        end
      end
    end
  end
end
