# typed: false
# frozen_string_literal: true

module Spam
  # Provides shared methods for checking if the
  # user who owns the content is spammy
  #
  # Used for things like PullRequest, IssueComment, DiscussionPostReply.
  module ContentUserIsSpammy
    # returns true if the viewer is site admin and the content's user is marked as spammy
    def user_is_spammy(viewer)
      return @user_is_spammy if defined?(@user_is_spammy)
      @user_is_spammy = async_user_is_spammy(viewer).sync
    end

    # returns true if the viewer is site admin and the content's user is marked as spammy
    def async_user_is_spammy(viewer)
      Promise.resolve(false) unless viewer.try(:site_admin?)
      async_user.then do |user|
        user ? user.spammy? : false
      end
    end
  end
end
