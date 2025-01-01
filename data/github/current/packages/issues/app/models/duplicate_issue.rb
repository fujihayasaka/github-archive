# typed: true
# frozen_string_literal: true

class DuplicateIssue < ApplicationRecord::Domain::IssuesPullRequests
  include Permissions::Attributes::Wrapper

  # Thease attributes should never be updated, as it represents a single event at a given point of time
  attr_readonly :issue_id, :canonical_issue_id, :repository_id

  self.permissions_wrapper_class = Permissions::Attributes::DuplicateIssue

  # `readonly` on the association and `attr_readonly :repository_id` need to be used together here.
  # One is preventing the now existing `repository_id` column from being altered, while the other prevents the
  # also existing association to be changed after creation. This will change once we switch to modelling the repository
  # association through the foreign key relationship.
  belongs_to :issue, -> { readonly }
  belongs_to :canonical_issue, class_name: "Issue"
  belongs_to :actor, class_name: "User"

  # The Repository of the duplicate Issue
  belongs_to :repository, -> { readonly }

  before_validation :set_repository_id
  validates :issue, :canonical_issue, :actor, presence: true
  validates :issue_id, uniqueness: { scope: :canonical_issue_id }
  validates :repository_id, presence: true, on: :create
  validate :issue_is_not_canonical_issue

  after_save :notify_socket_subscribers # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :marked_as_duplicate, -> { where(duplicate: true) }

  scope :marked_as_not_duplicate, -> { where(duplicate: false) }

  scope :with_duplicate_issue, ->(issue_id) { where(issue_id: issue_id) }

  scope :with_canonical_issue, ->(issue_id) { where(canonical_issue_id: issue_id) }

  scope :with_canonical_and_duplicates, ->(canonical_and_duplicate_issue_ids) {
    conditions = ["(canonical_issue_id = ? AND issue_id = ?)"] * canonical_and_duplicate_issue_ids.size
    T.unsafe(self).where(conditions.join(" OR "), *canonical_and_duplicate_issue_ids.flatten)
  }

  # Public: Returns a DuplicateIssue instance representing the given pair of issues.
  #
  # issue - the duplicate Issue
  # canonical_issue - the original/source/authoritative Issue
  # is_duplicate - whether the `issue` should be marked as a duplicate of `canonical_issue`;
  #                defaults to true; pass false for un-marking what was previously considered a
  #                duplicate
  # user - the User who marked or unmarked the `issue` as a duplicate of `canonical_issue`
  #
  # Returns DuplicateIssue.
  def self.find_or_build_for(issue:, canonical_issue:, user:, is_duplicate: true)
    dupe_issue = with_duplicate_issue(issue).with_canonical_issue(canonical_issue).first ||
      new(issue: issue, canonical_issue: canonical_issue)
    dupe_issue.duplicate = is_duplicate
    dupe_issue.actor = user
    dupe_issue
  end

  # Public: Returns a promise which resolves to true if this DuplicateIssue is allowed
  #   to be changed by the given User.
  def async_editable_by?(user)
    return Promise.resolve(false) unless user
    async_actor.then do |actor|
      next Promise.resolve(true) if actor == user

      async_repository.then do |repo|
        next Promise.resolve(false) unless repo
        repo.async_writable_by?(user)
      end
    end
  end

  # Public: Can the user unmark an issue as duplicated?
  #
  # Returns Boolean
  def can_unmark_as_duplicate?(user)
    return false unless user

    ::Permissions::Enforcer.authorize(
      action: :unmark_as_duplicate,
      actor: user,
      subject: self,
    ).allow?
  end

  # Internal: Do WebSocket notification about the duplicate status of the issue being changed.
  #
  # Returns socket ID string that was notified.
  def notify_socket_subscribers
    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "issue ##{issue_id} duplicate status changed",
    }
    channel = GitHub::WebSocket::Channels.issue(issue)
    GitHub::WebSocket.notify_issue_channel(issue, channel, data)
  end

  private

  def set_repository_id
    self.repository_id = issue&.repository_id
  end

  def issue_is_not_canonical_issue
    return unless issue && canonical_issue

    if issue == canonical_issue
      errors.add(:issue, "cannot be the same as canonical issue")
    end
  end
end
