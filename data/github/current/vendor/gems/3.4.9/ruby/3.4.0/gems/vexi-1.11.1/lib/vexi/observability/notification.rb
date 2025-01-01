# frozen_string_literal: true
#              

require "active_support"
require "active_support/notifications"

module Vexi
  module Observability
    # Vexi activesupport notifications instrumenter
    class Notification
      include Instrumenter

      def instrument(name, payload = {})
        ActiveSupport::Notifications.instrument(name, payload)
      end
    end
  end
end
