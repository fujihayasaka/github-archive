# typed: true
# frozen_string_literal: true

# ActiveRecord mixin for things that can be @mentioned with subscription logic.
# This includes the following models:
#   Milestone
#   Issue
#   IssueComment
#   CommitComment
#   CommitMention
#   PullRequestReview
#   PullRequestReviewComment
#   DiscussionPost
#   DiscussionPostReply
#
# This makes use of methods from the SubscribableThread module.
#
# Models that mix this in must implement a #subscribe_mentioned method that
# takes an Array of users and does whatever is necessary to subscribe them.
module Notifications
  module Mentionable
    extend T::Helpers
    extend T::Sig
    include GitHub::UserContent
    include Notifications::SubscribableThread

    requires_ancestor { ActiveRecord::Base }

    abstract!

    sig { abstract.returns(User) }
    def notifications_author; end

    # Subscribe a list of mentioned users to this object. This also creates
    # mentioned events.
    #
    # mentions - Array of users, or User scope, that were mentioned. This defaults to
    #            users
    #            mentioned in the issue body but a custom array may be passed
    #            from associated comment models and whatnot too.
    #
    # Returns nothing.
    sig { params(mentions: T::Enumerable[User], author: T.nilable(User)).void }
    def subscribe_mentioned(mentions = mentioned_users, author = nil)
      author ||= self.respond_to?(:user) ? T.unsafe(self).user : nil
      return if author && author.spammy?

      GitHub.dogstats.histogram("mentionable.mentioned_users", mentioned_users.size)
      GitHub.dogstats.time("mentionable.subscribe_mentioned_users") do
        subscribable_user_mentions(mentions, author) do |mentionee, _author|
          subscribe mentionee, :mention
        end
      end
    end

    private

    # Internal: Normalizes and compacts the mentions.
    #
    # user_mentions - Array of mentioned Users.
    # author   - Author of the content being posted.  Defaults to #user.
    # &block   - The block that is called with mentionee.
    #
    # Yields mentionees and a User author, no more than once for unique mentionees. Returns nothing.
    def subscribable_user_mentions(user_mentions, author = nil, &block)
      author ||= notifications_author
      normalize_mentions(user_mentions).each do |user_mentionee|
        block.call(user_mentionee, author)
      end
    end

    def normalize_mentions(mentions)
      mentions.to_a.uniq.compact
    end
  end
end
