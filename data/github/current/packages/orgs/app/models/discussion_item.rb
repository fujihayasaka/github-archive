# typed: false
# frozen_string_literal: true

module DiscussionItem
  extend  ActiveSupport::Concern

  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include Instrumentation::Model
  include NotificationsContent::WithCallbacks
  include Reaction::Subject::TeamContext
  include UserContentEditable

  included do
    attribute :body, StringFromBinary.new

    validate :non_empty_body
  end

  # In order to render team mentions in the body, we need to provide the organization
  # See GitHub::UserContent#async_body_context
  def async_organization
    async_team.then(&:async_organization)
  end

  def organization
    async_organization.sync
  end

  # Implements Reaction::Subject#readable_by?.
  #
  # Also allows us to prevent leaking private posts through notifications via
  # Newsies::PolicyManager#reason_to_stop_delivery?.
  def readable_by?(user)
    async_readable_by?(user).sync
  end

  def async_readable_by?(user)
    raise NotImplementedError, self.class.name
  end

  def async_performed_via_integration
    Promise.resolve(nil)
  end

  def viewer_can_update?(viewer)
    async_viewer_can_update?(viewer).sync
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    async_programmatic_actor_reasons = if viewer.can_have_granular_permissions?
      async_is_programmatic_actor_with_write_access?(viewer).then do |has_access|
        has_access ? [] : [:insufficient_access]
      end
    else
      Promise.resolve([])
    end

    async_user_reasons = async_readable_by?(viewer).then do |readable|
      readable ? [] : [:insufficient_access]
    end

    Promise
      .all([async_programmatic_actor_reasons, async_user_reasons])
      .then do |programmatic_actor_reasons, user_reasons|

      (programmatic_actor_reasons + user_reasons).uniq
    end
  end

  def viewer_can_delete?(viewer)
    async_viewer_can_delete?(viewer).sync
  end

  # Can the given viewer delete this team discussion?
  #
  # viewer - One of {IntegrationInstallation, Bot, ProgrammaticAccessBot, (non-bot) User}.
  #
  # Returns a Promise of a Boolean.
  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer

    async_programmatic_actor_can_delete = if viewer.can_have_granular_permissions?
      async_is_programmatic_actor_with_write_access?(viewer)
    else
      Promise.resolve(true)
    end

    async_user_can_delete = async_readable_by?(viewer).then do |readable|
      next false unless readable
      next true if viewer.id == user_id

      async_team.then { |team| team.async_adminable_by?(viewer) }
    end

    Promise
      .all([async_programmatic_actor_can_delete, async_user_can_delete])
      .then(&:all?)
  end

  def async_is_programmatic_actor_with_write_access?(actor)
    raise NotImplementedError, self.class.name
  end

  # cumulative_previous_changes - Hash of attribute changes to use instead of the standard
  #                               `previous_changes` hash. This allows to accumulate changes that
  #                               span multiple database commits and instrument them just once.
  def event_payload(cumulative_previous_changes: nil)
    payload = {
      body: body,
      number: number,
      user: user,
      updated_at: updated_at,
    }

    changes = cumulative_previous_changes || previous_changes
    payload[:old_body] = changes[:body].first if changes.key?(:body)

    payload
  end

  # Implements NotificationsContent#unsubscribable_users.
  def unsubscribable_users(users)
    commenter_ids = Set.new(notifications_thread.replies.select("DISTINCT(user_id)"))
    users.reject { |user| commenter_ids.include?(user.id) }
  end

  def author_subscribe_reason
    notifications_thread == self ? "author" : "comment"
  end

  # Overrides SubscribableThread#subscribable_team_members to prevent subscribing unauthorized
  # users to private posts.
  def subscribable_team_members(team)
    super(team).select do |member|
      notifications_thread.async_readable_by?(member, preloaded_team_member_ids: preloaded_team_member_ids).sync
    end
  end

  private

  def non_empty_body
    errors.add(:body, "cannot be blank") if body&.strip.blank?
  end

  # Internal: Overrides Mentionable#subscribable_user_mentions to prevent subscribing unauthorized
  # users to private posts.
  def subscribable_user_mentions(user_mentions, author = nil, &block)
    super(user_mentions, author) do |mentionee, author|
      viewer_can_read = notifications_thread
        .async_readable_by?(mentionee, preloaded_team_member_ids: preloaded_team_member_ids)
        .sync
      return unless viewer_can_read
      block.call(mentionee, author)
    end
  end

  def preloaded_team_member_ids
    return @preloaded_team_member_ids if defined?(@preloaded_team_member_ids)

    @preloaded_team_member_ids = nil
    if notifications_thread.private?
      @preloaded_team_member_ids = Team.members_of(team.id, immediate_only: false).pluck(:id)
    end

    @preloaded_team_member_ids
  end
end
