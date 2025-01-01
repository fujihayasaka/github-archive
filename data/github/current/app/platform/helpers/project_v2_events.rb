# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module ProjectV2Events
      def self.is_project_v2_event_type?(event_type)
        [
          Platform::Objects::AddedToProjectV2Event,
          Platform::Objects::RemovedFromProjectV2Event,
          Platform::Objects::ProjectV2ItemStatusChangedEvent,
          Platform::Objects::ConvertedFromDraftEvent
        ].include?(event_type)
      end
    end
  end
end
