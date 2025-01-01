# typed: false
# frozen_string_literal: true

module FeedPostComment::ReactionsDependency
  extend ActiveSupport::Concern

  include GitHub::Memoizer
  include Reactable
  include Reaction::Subject

  included do
    has_many :reactions, as: :subject
  end

  def react(actor:, content:)
    Reaction.react(user: actor, subject_id: self.id, subject_type: self.class.name, content: content)
  end

  def unreact(actor:, content:)
    Reaction.unreact(user: actor, subject_id: self.id, subject_type: self.class.name, content: content)
  end

  memoize def async_user
    async_user
  end

  def async_readable_by?(user)
    true
  end

  memoize def reaction_admin
    async_reaction_admin.sync
  end

  memoize def async_reaction_admin
    async_user
  end

  def reaction_path
    return @reaction_path if defined?(@reaction_path)
    @reaction_path = async_reaction_path.sync
  end

  def async_reaction_path
    Promise.resolve(
      UrlHelpers.feed_post_comment_update_reaction_path(feed_post, self)
    )
  end

  def reactions_component(viewer:)
    DashboardFeed::ReactionsComponent.new(
      target_global_id: global_relay_id,
      show_reaction_selector: false,
      reaction_path: UrlHelpers.feed_post_comment_update_reaction_path(feed_post, self),
      emotions: Discussion.emotions,
      reaction_count_by_content: self.prelude_user_logins_by_reaction,
      viewer_reaction_contents: viewer_reaction_contents(viewer: viewer)
    )
  end

  def viewer_reaction_contents(viewer:)
    self.prelude_user_logins_by_reaction.filter_map do |content, user_logins|
      content if user_logins.include?(viewer.display_login)
    end
  end

  def notify_socket_subscribers
    # no-op
  end
end
