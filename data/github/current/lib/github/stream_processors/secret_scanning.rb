# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SecretScanning
      autoload :AlertEventsProcessor, "github/stream_processors/secret_scanning/alert_events_processor"
    end
  end
end
