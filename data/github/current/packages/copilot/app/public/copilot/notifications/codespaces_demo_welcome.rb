# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# This notification is a special flower. It's for users in a Codespaces/Copilot Demo Playgroud
#
# When the user first boots up the Codespace, their extension will phone home - we will give then NO notification
# At the 30 min mark, their extension will phone home again - we will give them a notification welcoming them
#   this is that
module Copilot
  module Notifications
    class CodespacesDemoWelcome < NotificationBase
      def message
        "We are thrilled that you’re enjoying the demo."
      end

      def link
        COPILOT_PRICING_PAGE
      end

      def weight
        100
      end

      def send_condition
        super do
          return false unless @copilot_user.codespaces_demo_request_allowed?

          # this assumes that the value has been processed in the auth.rb logic first
          @copilot_user.codespaces_demo_session_value == CODESPACES_DEMO_SECOND_VALUE
        end
      end
    end
  end
end
