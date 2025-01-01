# typed: true
# frozen_string_literal: true

module Discussion::NewsiesAdapter
  extend T::Helpers
  extend T::Sig
  include Notifications::SubscribableThread

  requires_ancestor { Discussion }

  URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/discussions/{number}").freeze
  ORG_URI_TEMPLATE = Addressable::Template.new("/orgs/{owner}/discussions/{number}").freeze

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer

    # Preload repo and its owner for use by lib/permissions/enforcer.rb for a
    # Discussion subject when checking authzd permissions.
    async_repository_and_owner.then do
      deletable_by?(viewer)
    end
  end

  sig { returns Symbol }
  def author_subscribe_reason
    :author
  end

  sig { params(candidate: T.untyped).returns(T.untyped) }
  def subscribable_by?(candidate)
    notifications_list&.public? || notifications_list&.readable_by?(candidate)
  end

  sig { returns Discussion }
  def notifications_thread
    T.cast(self, Discussion)
  end

  sig { returns T.nilable(Repository) }
  def notifications_list
    async_notifications_list.sync
  end

  sig { returns Promise[T.nilable(Repository)] }
  def async_notifications_list
    async_repository
  end

  sig { returns T.nilable(T::Boolean) }
  def deliver_notifications?
    return false unless open? || closed?
    return false unless repository&.active?
    return false if repository&.disable_discussions_notifications_flag_enabled?
    return false if converting?
    return false if updated_at && converted_at && T.must(updated_at) <= converted_at

    # If feature is enabled for this repository, we can deliver notifications
    repository&.discussions_active?
  end

  sig { returns(T.untyped) }
  def get_notification_summary
    return if destroyed?
    list = Newsies::List.new("Repository", repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, self)
  end

  sig { void }
  def destroy_notification_summary
    repo = repository || Repository.new.tap { |r| r.id = repository_id }
    GitHub.newsies.async_delete_all_for_thread(repo, self)
  end

  sig { params(summary: T.untyped).returns(T.untyped) }
  def update_notification_rollup(summary)
    suffix = summarizable_changed?(:title, :body) ? :changed : :unchanged
    GitHub.dogstats.increment("newsies.rollup", tags: ["type:#{suffix}"])

    summary.summarize_discussion(self)
  end

  sig { returns T.nilable(User) }
  def notifications_author
    user
  end

  sig { returns Promise[T.nilable(Repository)] }
  def async_entity
    async_repository
  end

  sig { returns T.nilable(Repository) }
  def entity
    repository
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo.  Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of User that can be unsubscribed.
  sig { params(users: T.untyped).returns(T.untyped) }
  def unsubscribable_users(users)
    commenters = Set.new
    comments.select("DISTINCT user_id").each do |comment|
      commenters << comment.user_id
    end
    commenters.add(user_id)
    users.reject { |user| commenters.include?(user.id) }
  end

  sig { returns String }
  def message_id
    "<#{repository&.name_with_display_owner}/repo-discussions/#{number}@#{GitHub.urls.host_name}>"
  end

  sig { returns Promise[T.untyped] }
  def async_repository_and_owner
    async_repository.then(&:async_owner)
  end

  # Absolute permalink URL for the discussion.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                discussion.permalink(include_host: false) => `/github/github/discussions/1`
  #
  # Returns a String URL to view this discussion.
  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    if organization_discussion?
      "#{GitHub.url if include_host}/orgs/#{repository&.owner_display_login}/discussions/#{to_param}"
    else
      "#{repository&.permalink(include_host: include_host)}/discussions/#{to_param}"
    end
  end
  alias_method :url, :permalink

  sig { returns Promise[String] }
  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository_and_owner.then do
      if organization_discussion?
        ORG_URI_TEMPLATE.expand(owner: repository&.owner_display_login, number: number)
      else
        URI_TEMPLATE.expand(
          owner:  repository&.owner_display_login,
          name:   repository&.name,
          number: number,
        )
      end
    end
  end
end
