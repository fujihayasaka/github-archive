# typed: true
# frozen_string_literal: true

class DiscussionTransfer < ApplicationRecord::Domain::Discussions
  extend T::Sig
  include Instrumentation::Model

  DEFAULT_TRANSFER_TRAVERSAL_DEPTH = 10

  REASONS = %w[
    Misfiled
    Sensitive
    Reorganization
    Other
  ].freeze

  enum :state, {
    started: 0,
    done: 1,
    errored: 2,
  }

  belongs_to :old_repository, class_name: "Repository", required: true
  belongs_to :old_discussion, class_name: "Discussion", required: true

  belongs_to :new_repository, class_name: "Repository", required: true
  belongs_to :new_discussion, class_name: "Discussion", required: true
  belongs_to :new_discussion_event, class_name: "DiscussionEvent"

  belongs_to :actor, class_name: "User", required: true

  before_validation :set_old_discussion_number, on: :create
  before_validation :set_old_repository, on: :create

  validates :old_discussion_number, presence: true
  validates :reason, inclusion: { in: REASONS, allow_nil: true }
  validate :ensure_transferrable_state
  validate :actor_permissions
  validate :repos_not_archived
  validate :repos_have_discussions
  validate :transferrable_by_actor
  validate :with_same_owner
  validate :not_transferring_private_to_public

  scope :for_new_repository, ->(repo) { where(new_repository_id: repo) }
  scope :for_old_repository, ->(repo) { where(old_repository_id: repo) }
  scope :for_old_discussion, ->(discussion) { where(old_discussion_id: discussion) }
  scope :by_actor, ->(user) { where(actor_id: user) }

  # Finds a DiscussionTransfer for a repository and discussion number
  # for following discussions that may have been transferred multiple
  # times.
  #
  # Returns a (DiscussionTransfer, Boolean) with the transfer that contains
  # the new discussion and a boolean for whether a transfer exists but the new
  # discussion could not be found.
  sig { params(repository: T.untyped, number: T.untyped).returns(T.untyped) }
  def self.find_from(repository:, number:)
    first_transfer = find_by(old_repository_id: repository.id, old_discussion_number: number)

    if first_transfer
      last_transfer = unravel_transfer_chain(first_transfer: first_transfer)
      return [last_transfer, true]
    end

    [nil, false]
  end

  sig { params(original_id: T.untyped).returns(T.untyped) }
  def self.find_new_id_by_original_id(original_id:)
    first_transfer = find_by(old_discussion_id: original_id)

    if first_transfer
      return unravel_transfer_chain(first_transfer: first_transfer)&.new_discussion_id
    end

    nil
  end

  sig { params(first_transfer: T.untyped).returns(T.untyped) }
  def self.unravel_transfer_chain(first_transfer:)
    DEFAULT_TRANSFER_TRAVERSAL_DEPTH.times.inject(first_transfer) do |transfer|
      # Is this the final transfer? Return it!
      return transfer if transfer.new_discussion

      # Can we find a new discussion transfer? If not, bail out
      return nil unless next_transfer = find_by(old_discussion_id: transfer.new_discussion_id)

      next_transfer
    end
    nil
  end

  sig { params(staff_user: T.nilable(User)).void }
  def instrument_transfer_event(staff_user = nil)
    audit_log_user = if staff_user&.site_admin?
      staff_user
    else
      actor
    end
    old_discussion&.instrument(:transfer, actor: audit_log_user, discussion_transfer: self)
  end

  private

  sig { void }
  def set_old_discussion_number
    old_discussion = self.old_discussion
    return unless old_discussion
    self.old_discussion_number = old_discussion.number
  end

  sig { void }
  def set_old_repository
    old_discussion = self.old_discussion
    return unless old_discussion
    self.old_repository = old_discussion.repository
  end

  sig { void }
  def ensure_transferrable_state
    old_discussion = self.old_discussion
    return unless old_discussion
    valid_state = old_discussion.open? || old_discussion.closed?

    if !valid_state || old_discussion.locked?
      errors.add(:old_discussion, "cannot be locked, being transferred, or in an error state")
    end
  end

  sig { void }
  def actor_permissions
    actor = self.actor
    old_repository = self.old_repository
    new_repository = self.new_repository
    return unless actor && old_repository && new_repository

    acting_user = if actor.bot?
      T.cast(actor, Bot).installation
    else
      actor
    end

    unless old_repository.resources.contents.writable_by?(acting_user)
      errors.add(:actor, "must have write permission on current repository")
    end

    unless new_repository.resources.contents.writable_by?(acting_user)
      errors.add(:actor, "must have write permission on new repository")
    end
  end

  sig { void }
  def repos_not_archived
    if new_repository&.archived?
      errors.add(:new_repository, "must not be archived")
    end

    if old_repository&.archived?
      errors.add(:old_repository, "must not be archived")
    end
  end

  sig { void }
  def repos_have_discussions
    old_repository = self.old_repository
    new_repository = self.new_repository
    return unless new_repository && old_repository

    unless new_repository.discussions_on?
      errors.add(:new_repository, "must have discussions enabled")
    end

    unless old_repository.discussions_on?
      errors.add(:old_repository, "must have discussions enabled")
    end
  end

  sig { void }
  def transferrable_by_actor
    old_discussion = self.old_discussion
    return unless old_discussion

    unless old_discussion.transferrable_by?(actor)
      errors.add(:old_discussion, "is not transferrable")
    end
  end

  sig { void }
  def with_same_owner
    old_repository = self.old_repository
    new_repository = self.new_repository
    return unless new_repository && old_repository

    unless new_repository.owner_id == old_repository.owner_id
      errors.add(:new_repository, "must have the same owner as the current repository")
    end
  end

  sig { void }
  def not_transferring_private_to_public
    if old_repository&.private? && new_repository&.public?
      errors.add(:old_discussion,
        "cannot be transferred from a private repository to a public repository")
    end
  end
end
