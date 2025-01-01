# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class CopilotAbuseWarning < NotificationBase
      def message
        "Our systems have detected suspicious Copilot activity coming from your account. Please review our terms of service. Further suspicious activity could lead to your Copilot access being temporarily revoked."
      end

      def title
        "Terms of Service"
      end

      def link
        COPILOT_SPECIFIC_TERMS
      end

      def send_condition
        super do
          copilot_user.has_been_warned?
        end
      end
    end
  end
end
