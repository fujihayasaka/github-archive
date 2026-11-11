# typed: false
# frozen_string_literal: true

class DiscussionPostReply < ApplicationRecord::Ballast
  include DiscussionItem
  include DiscussionPostReply::NewsiesAdapter
  include EmailReceivable
  include Reactable
  include Spam::ContentUserIsSpammy

  belongs_to :user
  belongs_to :discussion_post

  attr_readonly :number

  before_create :set_number
  after_commit :notify_websocket, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  after_commit :subscribe_and_notify,            on: :create
  after_commit :update_subscriptions_and_notify, on: :update

  has_many :reactions, as: :subject
  destroy_dependents_in_background :reactions

  def team=(team)
    discussion_post.team = team
  end

  def team
    discussion_post.team
  end

  def async_team
    async_discussion_post.then do |discussion_post|
      discussion_post.async_team
    end
  end

  alias_method :entity, :team

  def notifications_author
    user
  end

  def notifications_thread
    async_notifications_thread.sync
  end

  def async_notifications_thread
    async_discussion_post
  end

  def async_notifications_list
    async_team
  end

  # Implements abstract Summarizable#get_notification_summary method.
  def get_notification_summary
    if discussion_post && team
      list = Newsies::List.new("Team", team.id)
      GitHub.newsies.web.find_rollup_summary_by_thread(list, discussion_post)
    end
  end

  # Returns the entity (team) required by GitHub::UserContent
  def async_entity
    async_team.then do |team|
      # GitHub::UserContent calls `entity.to_s` to generate a version string.
      # As `Team#to_s` delegates to `Team#combined_slug` we also have to load
      # the team's organization async.
      team.async_organization.then do
        team
      end
    end
  end

  # Sets the name of an internal method used to process email replies in
  # Jobs::EmailReply#process_reply.
  def email_reply_creation_method
    "reply_to_team_discussion_comment"
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_team.then(&:async_target_for_conditional_access)
  end

  def async_readable_by?(user)
    Promise.resolve(false) unless user
    async_discussion_post.then { |discussion| discussion.async_readable_by?(user) }
  end

  def platform_type_name
    "TeamDiscussionComment"
  end

  # Does the given actor have write access to team discussions?
  #
  # actor - Either an IntegrationInstallation, Bot or ProgrammaticAccessBot.
  #
  # Returns a Promise of a Boolean.
  private def async_is_programmatic_actor_with_write_access?(actor)
    Promise.resolve(false) unless actor
    async_discussion_post.then do |discussion|
      discussion.async_is_programmatic_actor_with_write_access?(actor)
    end
  end

  private

  def set_number
    Sequence.create(discussion_post) unless Sequence.exists?(discussion_post)
    self.number = Sequence.next(discussion_post)
  end

  def notify_websocket
    GitHub::WebSocket.notify_discussion_post_channel(discussion_post, channel, {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "discussion post ##{discussion_post_id} updated",
    })
  end

  def channel
    GitHub::WebSocket::Channels.discussion_post(discussion_post)
  end

  # Writes a discussion_post_reply.update event to the ActiveSupport::Notifications stream (which is
  # ultimately consumed by the audit log for instance).
  def instrument_update
    instrument(:update)
  end

  # Writes a discussion_post_reply.destroy event to the ActiveSupport::Notifications stream (which
  # is ultimately consumed by the audit log for instance).
  def instrument_destroy
    instrument(:destroy)
  end

  # Defines the namespace for audit log events.
  def event_prefix
    "discussion_post_reply"
  end

  # Extends DiscussionItem::event_payload to create the payload for audit log events.
  def event_payload
    payload = { discussion_post_id: discussion_post_id }

    # If possible, fill in more information about this reply's context. This may not always be
    # possible, because the parent discussion post may have already been deleted (e.g. if this is
    # executing in the context of dependent destroy).
    if discussion_post
      payload = payload.merge(
        discussion_post_number: discussion_post.number,
        org: team&.organization,
        team: team,
      )
    end

    super.merge(payload)
  end
end
