# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueEventsByEvent < Platform::Loader
      def self.load(issue_id:, event_type:)
        self.for(event_type).load(issue_id)
      end

      def initialize(event_type)
        @event_type = event_type
      end

      def fetch(issue_ids)
        IssueEvent.where(issue_id: issue_ids, event: @event_type).group_by(&:issue_id)
      end
    end
  end
end
