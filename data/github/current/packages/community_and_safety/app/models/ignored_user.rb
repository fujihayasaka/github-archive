# typed: false
# frozen_string_literal: true

class IgnoredUser < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include ActionView::Helpers::DateHelper

  belongs_to :ignored_by, class_name: "User", foreign_key: "user_id" # rubocop:todo Rails/InverseOf
  belongs_to :ignored, class_name: "User"
  belongs_to :blocked_from_content, polymorphic: true

  validate :ignored
  validate :ignored_by
  validate :ignored_is_a_user
  validate :cannot_block_org_member
  validate :cannot_block_billing_manager
  validate :not_already_blocking, on: :create
  validate :cannot_block_yourself
  validate :spammy_users_cannot_block
  validate :cannot_block_spammy_users
  validate :must_have_verified_email
  validate :time_limited_blocker_is_an_org
  validate :notify_blocker_is_an_org
  validate :blocked_from_content_needs_to_be_owned_by_ignored
  validate :blocked_from_content_needs_to_be_in_ignored_by_owned_repo
  validate :duration_is_allowed_amount

  MAX_NOTE_LENGTH = 100
  validates :note, length: { maximum: MAX_NOTE_LENGTH }, allow_nil: true

  after_create :send_email_to_ignored_user, if: :send_notification
  after_create :trigger_user_blocked_event, if: :send_notification
  after_create :enqueue_ignore_user
  after_commit :invalidate_user_feed_cache
  after_create_commit :instrument_creation
  after_destroy_commit :instrument_destroy
  after_commit :enqueue_clear_graph_data, on: [:create, :destroy]
  after_create_commit :enqueue_minimize_comments, if: :minimize_reason

  # Public: Returns IgnoredUsers where the given user(s) is the recipient of the block (the one
  # being ignored).
  scope :blocking, ->(user) { where(ignored_id: user) }

  # Public: Returns IgnoredUsers where the given user(s) is the one doing the blocking (the one who
  # is ignoring someone else).
  scope :blocked_by, ->(user) { where(user_id: user) }

  default_scope { where("expires_at IS NULL or expires_at > ?", Time.at((Time.now.to_f / 60).round * 60)) }

  attr_accessor :actor
  attr_accessor :send_notification
  attr_accessor :minimize_reason

  HUMANIZED_ATTRIBUTES = {
    ignored: "Blocked user",
    ignored_by: "Blocking user",
  }

  VALID_BLOCK_DURATIONS_IN_DAYS = [nil, 1, 3, 7, 30]

  # The code uses the verb "ignore", but user-facing docs use "block"
  def self.human_attribute_name(attr, options)
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  # Returns the duration in days as an int, or nil if no duration was set
  def duration
    ((expires_at - created_at) / 1.day).round if created_at && expires_at
  end

  def destroy(actor: nil)
    self.actor = actor
    super()
  end

  private

  # allow block_user instrumentation to remain in the user/org namespace for
  # backwards compatability with events formerly instrumented on the user model
  def event_prefix
    ignored_by.user? ? :user : :org
  end

  def event_payload
    {
      actor: actor,
      blocked_user: ignored,
      spammy: ignored_by.spammy?,
      user: (ignored_by if ignored_by.user?),
      org: (ignored_by if ignored_by.organization?),
    }.compact
  end

  def ignored_is_a_user
    unless ignored.respond_to?(:user?) && ignored.user?
      errors.add(:ignored, "is not a user")
    end
  end

  def cannot_block_org_member
    if ignored_by.is_a?(Organization) && ignored_by.direct_or_team_member?(ignored)
      errors.add(:ignored, "is an organization member")
    end
  end

  def cannot_block_billing_manager
    if ignored_by.is_a?(Organization) && ignored_by.billing_manager?(ignored)
      errors.add(:ignored, "is a billing manager of this organization")
    end
  end

  # Cannot use validates_uniqueness of because it doesn't take into account
  # The default scope, meaning expired blocks would be counted as a dupe.
  def not_already_blocking
    if IgnoredUser.exists?(ignored: ignored, ignored_by: ignored_by)
      errors.add(:ignored, "has already been blocked")
    end
  end

  def cannot_block_yourself
    if ignored_by == ignored
      errors.add(:ignored, "cannot be the blocking user")
    end
  end

  # Spammy users should not be able to block other users.
  # This is an unknown abuse vector. See https://git.io/fAZU2.
  def spammy_users_cannot_block
    if ignored_by.spammy?
      errors.add(:ignored_by, "has been flagged as spam")
    end
  end

  # If a user has been flagged as spammy, don't allow other users to block them,
  # unless the blocker can see this spammy user.
  def cannot_block_spammy_users
    if ignored.spammy? && ignored.hide_from_user?(ignored_by)
      errors.add(:ignored, "has been flagged as spam")
    end
  end

  def must_have_verified_email
    if ignored_by.must_verify_email?
      errors.add(:ignored_by, "cannot block without a verified email")
    end
  end

  def time_limited_blocker_is_an_org
    if expires_at && !ignored_by.organization?
      errors.add(:ignored_by, "cannot create a time-limited block")
    end
  end

  def notify_blocker_is_an_org
    if blocked_from_content && !ignored_by.organization?
      errors.add(:ignored_by, "cannot create a block with a notification")
    end
  end

  def send_email_to_ignored_user
    # Time cannot be serialized for the mailer so we build the string here
    duration_string = self.expires_at ? " for #{distance_of_time_in_words_to_now(self.expires_at)}" : nil
    AccountMailer.blocked_by_org(self.ignored_by, self.ignored, self.blocked_from_content, duration_string).deliver_later unless actor.blocked_by?(ignored)
  end

  def trigger_user_blocked_event
    blockable = if blocked_from_content.is_a?(Issue)
      blocked_from_content
    elsif blocked_from_content.respond_to?(:issue)
      blocked_from_content.issue
    end

    return unless blockable.present?
    blockable.trigger_user_blocked_event(self)
  end

  def blocked_from_content_needs_to_be_owned_by_ignored
    if blocked_from_content && blocked_from_content.user != ignored
      errors.add(:blocked_from_content, "must be owned by blocked user")
    end
  end

  def blocked_from_content_needs_to_be_in_ignored_by_owned_repo
    if blocked_from_content && blocked_from_content.repository.owner != ignored_by
      errors.add(:blocked_from_content, "must be content in a #{ignored_by.name} repository")
    end
  end

  def duration_during_create
    ((expires_at - Time.now) / 1.day).round if expires_at
  end

  def duration_is_allowed_amount
    errors.add(:expires_at, "is invalid") unless VALID_BLOCK_DURATIONS_IN_DAYS.include?(duration_during_create)
  end

  def enqueue_ignore_user
    IgnoreUserJob.perform_later(ignored_by.id, ignored.id)
  end

  def invalidate_user_feed_cache
    Conduit::KVBackedCache.invalidate_for(ignored_by)
  end

  # Private: Enqueue a job to remove graph caches for contributions on
  #          blocker's repos.
  #
  # Returns nothing.
  def enqueue_clear_graph_data
    ClearGraphDataOnBlockJob.perform_later(ignored_by.id, ignored.id)
  end

  # Private: Enqueue a job to minimize the blockee's comments in all of the
  #          blocker's repositories.
  #
  # Returns nothing.
  def enqueue_minimize_comments
    MinimizeAllCommentsOnRepoJob.perform_later(
      ignored_by,
      ignored,
      actor,
      minimize_reason,
    )
  end

  def instrument_creation
    # instrument for ActiveSupport::Notifications
    instrument :block_user,
               expires_at: expires_at,
               duration: duration,
               blocked_from_content_id: blocked_from_content_id,
               blocked_from_content_type: blocked_from_content_type,
               send_notification: send_notification,
               minimize_reason: minimize_reason,
               code_of_conduct_status: code_of_conduct_status

    GlobalInstrumenter.instrument "ignored_user", hydro_payload(:ACTION_IGNORED_USER_CREATED)
  end

  def instrument_destroy
    instrument :unblock_user

    GlobalInstrumenter.instrument "ignored_user", hydro_payload(:ACTION_IGNORED_USER_DELETED)
  end

  def hydro_payload(action)
    {
        actor: actor,
        blocked_from_content_id: blocked_from_content_id,
        blocked_from_content_type: blocked_from_content_type,
        action: action,
        expires_at: expires_at,
        ignored: ignored,
        ignored_by: ignored_by.is_a?(Organization) ? nil : ignored_by,
        ignored_by_org: ignored_by.is_a?(Organization) ? ignored_by : nil,
        minimize_reason: minimize_reason,
        repository: blocked_from_content&.repository,
    }
  end

  def code_of_conduct_status
    return !!blocked_from_content.repository.code_of_conduct&.url if blocked_from_content
    "unknown"
  end
end
