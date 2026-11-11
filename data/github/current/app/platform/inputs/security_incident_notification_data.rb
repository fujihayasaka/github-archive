# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityIncidentNotificationData < Platform::Inputs::Base
      description "Extra data for security incident notification."
      visibility :internal

      argument :key, String, "Data name.", required: true
      argument :value, String, "Data value.", required: true
    end
  end
end
