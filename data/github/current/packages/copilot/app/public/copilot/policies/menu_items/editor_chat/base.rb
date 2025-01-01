# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module EditorChat
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :chat_enabled?, :chat_disabled?, :no_chat_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_editor_chat_enabled"
          end
        end
      end
    end
  end
end
