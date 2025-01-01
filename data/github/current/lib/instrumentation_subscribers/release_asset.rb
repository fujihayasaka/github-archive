# typed: true
# frozen_string_literal: true

require "instrumentation/attachable_subscriber"

module InstrumentationSubscribers
  class ReleaseAsset
    include Instrumentation::AttachableSubscriber

    set_attachable_namespace :release_assets

    # Emitted when an Asset has been created for a policy (but not uploaded
    # yet).
    handle_event :policy

    # Emitted when an Asset has been uploaded through another service (like S3).
    handle_event :uploaded

    # Emitted when an Asset has been uploaded with a direct file.
    handle_event :file

    # Emitted when an Asset has been attached to something.
    handle_event :attachment

    # Emitted when an Asset has been downloaded.
    handle_event :download

    private

    def handle_in_development(action, started, ended, id, payload)
      if action == :download
        action = "Download #{payload[:size]}"
      end

      Rails.logger.warn "Release Asset: #{action}"
    end

    def handle_in_production(action, started, ended, id, payload)
      GitHub.dogstats.increment("release_asset", tags: ["action:#{action}"])
      if action == :download
        GitHub.dogstats.distribution("release_asset.download_size", payload[:size].to_i)
      end
    end
  end
end
