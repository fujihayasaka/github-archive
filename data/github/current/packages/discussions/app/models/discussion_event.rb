# typed: strict
# frozen_string_literal: true

class DiscussionEvent < ApplicationRecord::Domain::Discussions
  include Discussion::StateReasonable
  include GitHub::Memoizer

  NOTIFICATION_EVENTS = T.let(%w[
    closed
    reopened
  ], T::Array[String])

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain required: true
  belongs_to :discussion, required: true
  belongs_to :actor, class_name: "User"
  belongs_to :comment, class_name: "DiscussionComment"
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration, foreign_key: :performed_by_integration_id, class_name: "Integration"
  # rubocop:enable Rails/InverseOf
  belongs_to :issue

  has_one :discussion_transfer, foreign_key: "new_discussion_event_id" # rubocop:todo Rails/InverseOf

  before_validation :set_repository, on: :create
  after_commit :subscribe_and_notify, on: :create, if: :notify_for_event?

  enum :event_type, {
    locked: 0,
    unlocked: 1,
    answer_marked: 2,
    answer_unmarked: 3,
    transferred: 4,
    created_issue: 5,
    closed: 6,
    reopened: 7,
    answer_verified: 8,
    answer_unverified: 9,
  }

  validates :event_type, presence: true

  scope :by_actor, ->(actor) { where(actor_id: actor) }
  scope :for_discussion, ->(discussion) { where(discussion_id: discussion) }
  scope :for_organization, ->(org, only_repo_ids: nil) { joins(:discussion).merge(Discussion.for_organization(org, only_repo_ids: only_repo_ids)) }
  scope :for_comment, ->(comment) { where(comment_id: comment) }
  scope :for_repository, ->(repo) { where(repository_id: repo) }
  scope :for_comment_authored_by, ->(user) do
    joins(:comment).merge(DiscussionComment.for_user(user))
  end
  scope :still_marked_as_answer, -> do
    answer_marked.joins(:discussion).where("discussions.chosen_comment_id = discussion_events.comment_id")
  end
  scope :newest_first, -> { order("discussion_events.id DESC") }

  # Used for notifications
  delegate :subscribe, :subscribe_all, to: :discussion

  # Public: Get the repositories that discussions used to belong to, for the given 'transferred'
  #         discussion events, when the given viewer has permission to see those repositories.
  sig do
    params(
      events: T::Enumerable[DiscussionEvent],
      viewer: T.nilable(User)
    ).returns(T::Hash[Integer, T.nilable(Repository)])
  end
  def self.old_repositories_for_transfer_events(events:, viewer:)
    result = {}
    promises = events.map do |event|
      event.async_old_repository_for(viewer)
    end
    old_repos = Promise.all(promises).sync
    events.each_with_index do |event, i|
      result[event.id] = old_repos[i]
    end
    result
  end

  # Public: Get the previous repository the discussion belonged to before it was transferred,
  #         if this is a transfer event and the given viewer has permission to see that repository.
  sig { params(viewer: T.nilable(User)).returns(Promise[T.nilable(Repository)]) }
  def async_old_repository_for(viewer)
    # rubocop:todo GitHub/AvoidCast
    return T.cast(Promise.resolve(nil), Promise[T.nilable(Repository)]) unless transferred?
    # rubocop:enable GitHub/AvoidCast

    async_discussion_transfer.then do |transfer|
      next unless transfer

      transfer.async_old_repository.then do |old_repo|
        next unless old_repo

        old_repo.async_readable_by?(viewer).then do |is_readable|
          old_repo if is_readable
        end
      end
    end
  end

  sig { returns(T.nilable(User)) }
  def comment_author
    comment&.user
  end

  sig { returns(User) }
  def safe_actor
    actor || User.ghost
  end

  sig { returns(T::Boolean) }
  def marked_or_unmarked_answer?
    answer_marked? || answer_unmarked?
  end

  sig { returns(T::Boolean) }
  def verified_or_unverified_answer?
    answer_verified? || answer_unverified?
  end

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(viewer)
    async_comment.then do |comment|
      if comment
        comment.async_readable_by?(viewer).then do |comment_readable|
          next false unless comment_readable
          async_actor_visible_to?(viewer)
        end
      else
        async_discussion.then do |discussion|
          next false unless discussion

          discussion.async_readable_by?(viewer).then do |discussion_readable|
            next false unless discussion_readable
            async_actor_visible_to?(viewer)
          end
        end
      end
    end
  end

  sig { void }
  def deliver_notifications
    return unless notify_for_event?

    GitHub.newsies.trigger(
      discussion_event_notification,
      reason: :state_change,
      event_time: created_at,
    )
  end

  sig { returns(T.nilable(Discussion)) }
  def notifications_thread
    discussion
  end

  private

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_actor_visible_to?(viewer)
    async_actor.then do |actor|
      next true unless actor
      next false if actor.hide_from_user?(viewer)

      actor.async_blocked_by?(viewer).then do |blocked_by_viewer|
        !blocked_by_viewer
      end
    end
  end

  # Private: Indicates if the creation of this event should trigger a notification.
  sig { returns(T::Boolean) }
  def notify_for_event?
    return false unless NOTIFICATION_EVENTS.include?(event_type)
    return false if discussion&.converting?
    return false if discussion&.transferring?

    true
  end

  sig { returns(DiscussionEvent::Notification) }
  memoize def discussion_event_notification
    DiscussionEvent::Notification.new(event: self)
  end

  sig { void }
  def subscribe_and_notify
    SubscribeAndNotifyJob.perform_later(
      self,
      subscriber_reasons_and_ids: { state_change: [actor_id] },
      deliver_notifications: ::GitHub.send_notifications?,
    )
  end

  sig { void }
  def set_repository
    return unless this_repository = discussion&.repository
    self.repository = this_repository
  end
end
