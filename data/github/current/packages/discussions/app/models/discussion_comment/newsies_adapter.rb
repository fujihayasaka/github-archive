# typed: true
# frozen_string_literal: true

module DiscussionComment::NewsiesAdapter
  extend T::Helpers

  requires_ancestor { DiscussionComment }

  delegate :deliver_notifications?, to: :discussion

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    Promise.all([async_user, async_repository]).then do
      deletable_by?(viewer)
    end
  end

  sig { returns String }
  def message_id
    "<#{repository&.name_with_display_owner}/repo-discussions/#{discussion&.number}/comments/" \
      "#{id}@#{GitHub.urls.host_name}>"
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo. Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of User that can be unsubscribed.
  sig { params(users: T.untyped).returns(T.untyped) }
  def unsubscribable_users(users)
    discussion&.unsubscribable_users(users) || []
  end

  sig { returns(T.untyped) }
  def get_notification_summary
    discussion = self.discussion
    return unless discussion
    list = Newsies::List.new("Repository", discussion.repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, discussion)
  end

  sig { returns T.nilable(Discussion) }
  def notifications_thread
    discussion
  end

  sig { returns T.nilable(User) }
  def notifications_author
    user
  end

  sig { returns Promise[T.nilable(Repository)] }
  def async_notifications_list
    async_repository
  end

  sig { returns Promise[T.nilable(Repository)] }
  def async_entity
    async_repository
  end

  sig { returns T.nilable(Repository) }
  def entity
    repository
  end

  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    "#{discussion&.permalink(include_host: include_host)}##{dom_id}"
  end
  alias_method :url, :permalink

  sig { returns String }
  def author_subscribe_reason
    "comment"
  end
end
