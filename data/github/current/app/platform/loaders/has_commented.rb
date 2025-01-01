# typed: true
# frozen_string_literal: true

# Used to test if a user has commented on the given issue_id
#
module Platform
  module Loaders
    class HasCommented < Platform::Loader
      def self.load(issue, user_id)
        self.for(issue).load(user_id)
      end

      def initialize(issue)
        @issue = issue
      end

      def fetch(user_id)
        user_id = user_id.first

        # We're not supporting multiple users here with a load_all method because this is optimized to
        # be as fast as possible for a single user. This was originally added for use in user hovercards
        # in which we only care about a single user. If multiple users are ever needed please make the
        # attempt to preserve the single user limit query (#exists? uses a limit query under the hood).
        #
        # We're also using the repository_id here to take advantage of an existing index
        # index_issue_comments_on_repository_id_and_issue_id_and_user_id which required the repo id.
        has_commented = IssueComment.where(
          issue_id: @issue.id,
          user_id: user_id,
          repository_id: @issue.repository_id,
        ).exists?

        { user_id => has_commented }
      end
    end
  end
end
