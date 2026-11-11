# typed: strict
# frozen_string_literal: true

class PinnedIssueComment < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Memoizer
  include Instrumentation::Model
  include ::Repositories::BelongsToRepository

  belongs_to :issue
  belongs_to :issue_comment
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :pinned_by, class_name: "User", inverse_of: :pinned_issue_comments

  validates :issue, uniqueness: { message: "comment has already been pinned for this issue" }

  validate :validate_issue_is_not_pull_request
  validate :validate_issue_belongs_to_repository
  validate :validate_issue_comment_belongs_to_issue
  validate :validate_pinned_by_repository_permission

  before_validation :set_issue_from_issue_comment, on: :create
  before_validation :set_repository_from_issue, on: :create

  after_commit :instrument_pinned_issue_comment, on: :create, unless: :pinned_issue_comment_transfer? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_unpinned_issue_comment, on: :destroy, unless: :pinned_issue_comment_transfer? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Enables pinned issue transfer mode, allowing suppression of audit and hydro events.
  sig { params(blk: T.proc.void).returns(T.untyped) }
  def self.with_pinned_issue_comment_transfer(&blk)
    begin
      Thread.current[:pinned_issue_comment_transfer] = true
      yield
    ensure
      Thread.current[:pinned_issue_comment_transfer] = false
    end
  end

  sig { returns(T::Boolean) }
  def pinned_issue_comment_transfer?
    Thread.current[:pinned_issue_comment_transfer] || false
  end

  # While the pinned_by association is guaranteed to be present when the issue comment is first pinned, the user
  # may subsequently be deleted. In that case, we return the ghost user to avoid returning nil.
  sig { returns(User) }
  def safe_pinned_by
    pinned_by || User.ghost
  end

  sig { returns(User) }
  memoize def modifying_user
    ActiveRecord::Base.connected_to(role: :reading) do
      if (actor_id = GitHub.context[:actor_id]).present?
        User.find_by(id: actor_id) || safe_pinned_by
      else
        safe_pinned_by
      end
    end
  end

  # When displaying audit log event names to users, we want to use "issue_comment" instead of "pinned_issue_comment"
  # so that it's clearer what object the event is associated with. Pinned issue comments will appear as
  # issue_comment.pinned and issue_comment.unpinned events in the audit log.
  sig { returns(Symbol) }
  def event_prefix
    :issue_comment
  end

  # Returns a hash suitable for use as the context of the PinnedIssueComment record in an audit log event.
  sig { params(prefix: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: :pinned_issue_comment)
    {
      "#{prefix}_id".to_sym => id,
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = T.let({
      pinned_issue_comment: self,
      issue_comment:,
      issue:,
      repo: repository,
    }, T::Hash[Symbol, T.untyped])

    if (org = repository&.organization)
      payload[:org] = org
    end

    payload
  end

  private

  sig { void }
  def set_issue_from_issue_comment
    return if issue_id_came_from_user?

    self.issue_id = issue_comment&.issue_id
  end

  sig { void }
  def set_repository_from_issue
    return if repository_id_came_from_user?

    self.repository_id = issue&.repository_id
  end

  sig { void }
  def validate_issue_is_not_pull_request
    return unless (issue = self.issue)
    return unless issue.pull_request?

    errors.add(:issue, :cannot_be_pull_request)
  end

  sig { void }
  def validate_issue_belongs_to_repository
    return unless (repository_id = self.repository_id)
    return unless (issue = self.issue)
    return if issue.repository_id == repository_id

    errors.add(:issue, :invalid_association)
  end

  sig { void }
  def validate_issue_comment_belongs_to_issue
    return unless (issue_id = self.issue_id)
    return unless (issue_comment = self.issue_comment)
    return if issue_comment.issue_id == issue_id

    errors.add(:issue_comment, :invalid_association)
  end

  sig { void }
  def validate_pinned_by_repository_permission
    return unless (pinned_by = self.pinned_by)
    return unless (repository = self.repository)
    return if Issue::PermissionsDependency.can_manage_pinned_comment?(pinned_by, repository)

    errors.add(:pinned_by, :invalid_permissions, repository: repository.name_with_display_owner)
  end

  sig { void }
  def notify_graphql_subscribers
    return unless id = issue&.global_relay_id
    return unless pinned_comment_updated_id = issue_comment&.global_relay_id

    Platform::Schema.subscriptions.trigger(:issue_updated, { id: }, object: { pinned_comment_updated_id: })
  end

  sig { void }
  def instrument_pinned_issue_comment
    # Live updates
    notify_graphql_subscribers

    # Audit log event
    instrument :pinned, actor: pinned_by

    # Hydro event (uses GlobalInstrumenter which doesn't expand objects)
    GlobalInstrumenter.instrument("issue_comment.pinned", {
      issue_comment:,
      issue:,
      repository:,
      actor: pinned_by,
      state: :PINNED,
    })
  end

  sig { void }
  def instrument_unpinned_issue_comment
    # Live updates
    notify_graphql_subscribers

    # Audit log event
    instrument :unpinned, actor: modifying_user

    # Hydro event (uses GlobalInstrumenter which doesn't expand objects)
    GlobalInstrumenter.instrument("issue_comment.unpinned", {
      issue_comment:,
      issue:,
      repository:,
      actor: modifying_user,
      state: :UNPINNED,
    })
  end
end
