# typed: false
# frozen_string_literal: true

class DiscussionPost < ApplicationRecord::Ballast
  include DiscussionItem
  include DiscussionPost::NewsiesAdapter
  include DiscussionPost::DiscussionsDependency
  include Reactable
  include Spam::ContentUserIsSpammy
  include DiscussionPost::DiscussionsDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::DiscussionPost

  belongs_to :user
  belongs_to :pinned_by, class_name: "User", foreign_key: "pinned_by_user_id" # rubocop:todo Rails/InverseOf
  belongs_to :team
  belongs_to :discussion, foreign_key: "transferred_discussion_id", inverse_of: false
  has_many :replies, class_name: "DiscussionPostReply"
  destroy_dependents_in_background :replies

  has_many :reactions, as: :subject
  destroy_dependents_in_background :reactions

  alias_method :entity, :team
  alias_method :async_entity, :async_team

  attr_readonly :number
  attr_accessor :skip_instrument_update

  before_create :set_number
  after_commit :notify_websocket, on: :create
  after_commit :destroy_notification_dependents, on: :destroy
  after_commit :instrument_update, on: :update, unless: -> { skip_instrument_update }
  after_commit :instrument_destroy, on: :destroy

  after_commit :subscribe_and_notify,            on: :create
  after_commit :update_subscriptions_and_notify, on: :update

  # Use VARBINARY limit from the database
  TITLE_BYTESIZE_LIMIT = 1024

  attribute :title, StringFromBinary.new
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT },
    unicode: true

  def notifications_thread
    async_notifications_thread.sync
  end

  def async_notifications_thread
    Promise.resolve(self)
  end

  def async_notifications_list
    async_team
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_team.then(&:async_target_for_conditional_access)
  end

  def notifications_author
    user
  end

  def organization_id
    team&.organization_id
  end

  def async_viewer_can_pin?(viewer)
    if viewer.is_a?(Bot)
      return async_team.then do |team|
        team.async_organization.then do |org|
          org.resources.team_discussions.async_writable_by?(viewer)
        end
      end
    end

    Platform::Loaders::IsTeamMemberCheck.load(viewer.id, team_id).then do |is_team_member|
      next true if is_team_member
      async_team.then { |team| team.async_adminable_by?(viewer) }
    end
  end

  # Returns a Promise that resolves to a Boolean representing whether or not the
  # given viewer can view this discussion post.
  #
  # viewer - One of {IntegrationInstallation, Bot, ProgrammaticAccessBot, (non-bot) User}.
  #
  # preloaded_team_member_ids - Optional set of team member (User) IDs for
  #   members of this discussion's parent team. Can be provided by the caller to
  #   help us save a few database queries here. This is particularly useful if
  #   the caller anticipates triggering a code path that calls this method
  #   several times for different discussions belonging to the same team.
  #
  # Returns a Promise of a Boolean.
  def async_readable_by?(viewer, preloaded_team_member_ids: nil)
    return Promise.resolve(false) unless viewer

    async_team.then do |team|
      team.async_organization.then do |org|
        org.async_team_discussions_allowed?.then do |discussions_allowed|
          next false unless discussions_allowed
          next true if (preloaded_team_member_ids || []).include?(viewer.id)

          async_is_programmatic_actor_with_access?(viewer, :read).then do |programmatic_actor_has_read_access|
            next true if programmatic_actor_has_read_access

            # Reject any programmatic actor that gets this far, since it doesn't have
            # the necessary read permissions on team discussions.
            next false if viewer.can_have_granular_permissions?

            team.async_visible_to?(viewer).then do |team_is_visible|
              next false unless team_is_visible
              next true if public?

              org.async_adminable_by?(viewer).then do |org_is_adminable|
                org_is_adminable || (preloaded_team_member_ids.nil? &&
                  Platform::Loaders::IsTeamMemberCheck.load(viewer.id, team.id))
              end
            end
          end
        end
      end
    end
  end

  def title_changed?
    self.title.try(&:b) != self.title_was.try(&:b)
  end

  def pin_by(user_id:)
    self.pinned_at = Time.now
    self.pinned_by_user_id = user_id
  end

  def unpin
    self.pinned_at = nil
    self.pinned_by_user_id = nil
  end

  def pinned?
    !pinned_at.nil?
  end

  def public?
    !private?
  end

  # Implements abstract Summarizable#get_notification_summary method.
  def get_notification_summary
    list = Newsies::List.new("Team", team_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, self)
  end

  # Overrides Summarizable#update_notification_rollup.
  def update_notification_rollup(summary)
    suffix = summarizable_changed?(:body, :title) ? :changed : :unchanged
    GitHub.dogstats.increment("newsies.rollup.#{suffix}")

    summary.summarize_discussion_post(self)
  end

  # Writes a discussion_post.update event to the ActiveSupport::Notifications stream (which is
  # ultimately consumed by the audit log for instance).
  #
  # cumulative_previous_changes - Hash of attribute changes to use instead of the standard
  #                               `previous_changes` hash. This allows to accumulate changes that
  #                               span multiple database commits and instrument them just once.
  def instrument_update(cumulative_previous_changes: nil)
    instrument(:update, event_payload(cumulative_previous_changes: cumulative_previous_changes))
  end

  # Writes a discussion_post.destroy event to the ActiveSupport::Notifications stream (which is
  # ultimately consumed by the audit log for instance).
  def instrument_destroy
    instrument(:destroy)
  end

  # Defines the namespace for audit log events.
  def event_prefix
    "discussion_post"
  end

  # Extends DiscussionItem::event_payload to create the payload for audit log events.
  #
  # cumulative_previous_changes - Hash of attribute changes to use instead of the standard
  #                               `previous_changes` hash. This allows to accumulate changes that
  #                               span multiple database commits and instrument them just once.
  def event_payload(cumulative_previous_changes: nil)
    payload = {
      org: team&.organization,
      team: team,
      title: title,
      pinned_at: pinned_at,
      pinned_by_user: pinned_by,
      private: private?,
    }

    changes = cumulative_previous_changes || previous_changes

    payload[:old_title] = changes[:title].first if changes.key?(:title)
    payload[:old_pinned_at] = changes[:pinned_at].first if changes.key?(:pinned_at)
    if changes.key?(:pinned_by_user_id)
      payload[:old_pinned_by_user] = User.find_by_id(changes[:pinned_by_user_id].first)
    end

    super.merge(payload)
  end

  # Implements a required property of the Platform::Interfaces::Comment.
  #
  # You cannot create a discussion by email (you can only reply to one that way).
  def created_via_email
    false
  end

  # Sets the name of an internal method used to process email replies in
  # Jobs::EmailReply#process_reply.
  def email_reply_creation_method
    "reply_to_team_discussion"
  end

  def async_is_programmatic_actor_with_write_access?(actor)
    async_is_programmatic_actor_with_access?(actor, :write)
  end

  def platform_type_name
    "TeamDiscussion"
  end

  # Does the given actor have access to team discussions?
  #
  # actor - Either an IntegrationInstallation, Bot or ProgrammaticAccessBot. Bots can only write
  #         public discussions, but IntegrationInstallations can write both
  #         public and private discussions. This is safe because an
  #         IntegrationInstallation can never act on its own, so ultimately this
  #         will get called again with the installation's bot user or the human
  #         user on behalf of whom the installation is acting.
  #
  # action - Symbol representing the desired access level (:read or :write).
  #
  # Returns a Promise of a Boolean.
  private def async_is_programmatic_actor_with_access?(actor, action)
    unless actor.can_have_granular_permissions?
      return Promise.resolve(false)
    end

    async_team.then do |team|
      team.async_organization.then do |org|
        if action == :read
          org.resources.team_discussions.async_readable_by?(actor)
        elsif action == :write
          org.resources.team_discussions.async_writable_by?(actor)
        end
      end
    end
  end

  private

  def set_number
    Sequence.create(team, team.discussion_posts.count) unless Sequence.exists?(team)
    self.number = Sequence.next(team)
  end

  def notify_websocket
    GitHub::WebSocket.notify_discussion_post_channel(self, channel, { wait: default_live_updates_wait })
  end

  def channel
    GitHub::WebSocket::Channels.team(team)
  end

  def destroy_notification_dependents
    clear_newsies_thread
  end

  def clear_newsies_thread
    # If we don't have the team anymore, fake it.
    list = team || Team.new.tap { |t| t.id = team_id }
    GitHub.newsies.async_delete_all_for_thread(list, self)
  end
end
