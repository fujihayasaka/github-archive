# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :a_chat_enabled?, :a_chat_disabled?, :a_chat_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_a_chat"
          end
        end
      end
    end
  end
end
