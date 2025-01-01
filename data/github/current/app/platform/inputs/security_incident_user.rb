# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityIncidentUser < Platform::Inputs::Base
      description "Specifies a user and optional extra data for incident notification."
      visibility :internal

      argument :id, ID, "ID of a User account.", required: true
      argument :data, [Inputs::SecurityIncidentNotificationData],
        "Incident notification data key/value pairs for mustache template.",
        required: false
    end
  end
end
