# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityIncidentNotification < Platform::Inputs::Base
      description "Fields for sending a security incident notification."
      visibility :internal

      argument :from, String, "Notification email reply to address.", required: true
      argument :subject, String, "Notification email subject.", required: true
      argument :template, String, "Mustache template for notification", required: true
      argument :template_data, [Inputs::SecurityIncidentNotificationData],
        "Incident notification data key/value pairs for mustache template.",
        required: false
    end
  end
end
