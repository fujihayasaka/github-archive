# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SecretScanning
      autoload :AlertEventsProcessor, "github/stream_processors/secret_scanning/alert_events_processor"
      autoload :ScanCompletionProcessor, "github/stream_processors/secret_scanning/scan_completion_processor"
    end
  end
end
