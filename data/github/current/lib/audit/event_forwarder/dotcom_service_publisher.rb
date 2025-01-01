# typed: true
# frozen_string_literal: true

module Audit
  class EventForwarder
    # Public: Schedules background jobs to publish Audit Logs using the
    # GitHub.audit service. See github/lib/config/service.rb for the configuration
    # of the Audit service and what loggers are initilialized.
    class DotcomServicePublisher
      def publish(action, payload)
        # Will raise an error if an event is being logged that will expose staff information.
        GitHub.audit.ensure_staff_action_privacy(action, payload)

        if GitHub.audit.inline?
          ::LogAuditEntryJob.perform_now(action, payload)
        else
          ::LogAuditEntryJob.perform_later(action, payload)
        end
      end
    end
  end
end
