# typed: true
# frozen_string_literal: true

class IgnoredUser::Creator
  include ActiveModel::Validations

  attr_reader :blocker, :blockee, :actor, :duration, :blocked_from_content,
              :send_notification, :minimize_comments, :minimize_reason, :note

  alias_method :send_notification?, :send_notification
  alias_method :minimize_comments?, :minimize_comments

  validates :blocker, :blockee, :actor, presence: true
  validates :minimize_reason, presence: true, if: :minimize_comments?
  validate  :ensure_actor_authorized
  validate  :ensure_valid_minimize_reason

  # Public: Blocks a user.
  #
  # inputs[:blocker]              - The User who the blockee will be blocked from.
  # inputs[:blockee]              - The User who will be blocked by the blocker.
  # inputs[:actor]                - The User actor who is doing the actual blocking.
  # inputs[:duration]             - (optional) The Integer number of days that the
  #                                 blockee should be blocked for. If not
  #                                 specified, the duration is forever.
  # inputs[:blocked_from_content] - (optional) The OrgBlockable that blocking
  #                                 was initiated from.
  # inputs[:send_notification]    - (optional) A Boolean indicating if we should
  #                                 email the blockee to inform them that they were
  #                                 blocked. Defaults to `false`.
  # inputs[:minimize_comments]    - (optional) A Boolean indicating if we should
  #                                 minimize the blockee's comments in all
  #                                 repositories owned by the blocker. Defaults to
  #                                 `false`.
  # inputs[:minimize_reason]      - (optional) A String reason for minimizing the
  #                                 blockee's comments, if `minimize_comments` is true.
  # inputs[:note]                 - (optional) A String note to add to the block.
  #
  # Returns a IgnoredUser::Creator::Result.
  def self.call(inputs)
    new(**inputs).call
  end

  def initialize(
    blocker:,
    blockee:,
    actor:,
    duration: nil,
    blocked_from_content: nil,
    send_notification: false,
    minimize_comments: false,
    minimize_reason: nil,
    note: nil
  )
    @blocker              = blocker
    @blockee              = blockee
    @actor                = actor
    @duration             = duration.to_i > 0 ? duration.to_i : nil
    @blocked_from_content = blocked_from_content
    @send_notification    = send_notification
    @minimize_comments    = minimize_comments
    @minimize_reason      = minimize_reason
    @note                 = note
  end

  def call
    return Result.failure(errors: errors.full_messages) unless valid?

    expires_at = duration.days.from_now if duration

    block = IgnoredUser.new(
      ignored_by: blocker,
      ignored: blockee,
      actor: actor,
      expires_at: expires_at,
      blocked_from_content: blocked_from_content,
      send_notification: send_notification,
      minimize_reason: minimize_reason,
      note: note,
    )

    if block.save
      Result.success(block: block)
    else
      Result.failure(errors: block.errors.full_messages)
    end
  end

  class Result
    attr_reader :block, :success, :errors
    alias_method :success?, :success

    def initialize(block:, success:, errors:)
      @block   = block
      @success = success
      @errors  = errors
    end

    def self.success(block:)
      new(block: block, success: true, errors: [])
    end

    def self.failure(errors:)
      new(block: nil, success: false, errors: errors)
    end

    def message
      return @message if defined?(@message)
      return @message = nil unless success?

      notice = "#{block.ignored.display_login} has been blocked"
      notice += " from the #{block.ignored_by.display_login} organization" if block.ignored_by.organization?
      notice += " for #{block.duration} #{"day".pluralize(block.duration)}" if block.duration.present?
      notice += " and will receive an email notification" if block.send_notification
      notice += "."

      if raw_reason = block.minimize_reason
        reason = T.must(Platform::Enums::ReportedContentClassifiers.values[raw_reason]).value
        notice += " Their comments have been hidden as #{reason}."
      end

      @message = notice
    end
  end

  private

  def ensure_actor_authorized
    return unless blocker.present? && actor.present?

    unless blocker.blocked_users_manageable_by?(actor)
      errors.add(:actor, "is not authorized to block users")
    end
  end

  def ensure_valid_minimize_reason
    return unless minimize_comments?

    valid_reasons = Platform::Enums::ReportedContentClassifiers.values.keys
    return if valid_reasons.include?(minimize_reason)

    errors.add(:minimize_reason, "must be a valid reason")
  end
end
