# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ClosedIssueEvents < Platform::Loader
      def self.load(issue_id)
        self.for.load(issue_id)
      end

      def self.load_all(issue_ids)
        loader = self.for
        Promise.all(issue_ids.map { |id| loader.load(id) })
      end

      def fetch(issue_ids)
        ::IssueEvent.where(issue_id: issue_ids, event: "closed").order("issue_events.id ASC").group_by(&:issue_id)
      end
    end
  end
end
