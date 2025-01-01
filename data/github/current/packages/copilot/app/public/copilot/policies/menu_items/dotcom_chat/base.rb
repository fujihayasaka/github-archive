# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module DotcomChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :dotcom_chat_enabled?, :dotcom_chat_disabled?, :dotcom_chat_no_policy?, :dotcom_chat_configured?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_dotcom_chat"
          end
        end
      end
    end
  end
end
