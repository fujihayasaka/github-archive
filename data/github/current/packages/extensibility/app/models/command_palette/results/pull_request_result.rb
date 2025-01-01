# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class PullRequestResult < IssueResult
      def self.type
        PullRequest
      end
    end
  end
end
