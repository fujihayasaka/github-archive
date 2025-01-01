# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestLockedAt < Platform::Loader
      def self.load(pull_request_id)
        self.for.load(pull_request_id)
      end

      def fetch(pull_request_ids)
        ::Issue.
          where(pull_request_id: pull_request_ids).
          pluck(:pull_request_id, :locked_at).
          to_h
      end
    end
  end
end
