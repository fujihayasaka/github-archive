# typed: true
# frozen_string_literal: true

class ReviewRequest < ApplicationRecord::Domain::IssuesPullRequests
  extend T::Sig

  include GitHub::Relay::GlobalIdentification
  include LegacyImportable

  # Actions correspond to those defined in hydro.schemas.github.v1.PullRequestReviewRequest.Action
  UNKNOWN_ACTION = "ACTION_UNKNOWN"
  REQUESTED_ACTION = "REQUESTED"
  UNREQUESTED_ACTION = "UNREQUESTED"
  REREQUESTED_ACTION = "REREQUESTED"

  # Live update constants
  LIVE_UPDATE_EVENT_NAME = "reviewers_updated"

  belongs_to :pull_request, touch: true
  belongs_to :reviewer, polymorphic: true
  belongs_to :assigned_from_review_request, class_name: :ReviewRequest
  has_many :pull_request_reviews_review_requests
  has_many :pull_request_reviews, through: :pull_request_reviews_review_requests
  has_many   :reasons,
    autosave: true,
    class_name: "ReviewRequestReason",
    dependent: :delete_all,
    inverse_of: :review_request

  validates :repository_id, presence: true, on: :create
  validates :pull_request, presence: true
  validates :reviewer, presence: true
  validate  :ensure_requested_team_is_in_valid_org, unless: :importing?
  validate  :ensure_requested_reviewer_is_a_collaborator, unless: [:dismissed?, :importing?]
  validate  :one_pending_request_per_reviewer_and_pull_request

  before_validation :set_repository_id, on: :create
  after_create :trigger_review_requested_event, unless: [:deferred?, :importing?] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update :trigger_review_request_removed_event, if: :recently_dismissed?, unless: [:deferred?, :importing?] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :delegate_to_members, on: :create, unless: :deferred? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_state_changed, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_pull_request_socket_subscribers # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  delegate :repository, to: :pull_request

  scope :deferred, -> { where(deferred: true) }
  scope :ready, -> { where(deferred: false) }
  scope :dismissed, -> { where("review_requests.dismissed_at IS NOT NULL") }
  scope :not_dismissed, -> { where("review_requests.dismissed_at IS NULL") }
  scope :type_users, -> { where(reviewer_type: "User") }
  scope :type_teams, -> { where(reviewer_type: "Team") }

  # Accessor for differentiating unsaved review requests that represent future
  # requests once the PR is ready for review.
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :deferred_code_owner
  alias_method :deferred_code_owner?, :deferred_code_owner

  # Public: Finds all requests for one or more reviewers.
  #
  # mixed_reviewers   - One or more reviewers (Users and/or Teams)
  #
  # Returns an ActiveRecord::Relation.
  sig { params(mixed_reviewers: T.any(T::Array[T.any(User, Team)], User, Team)).returns(T.untyped) }
  def self.for(*mixed_reviewers)
    by_type = mixed_reviewers.flatten.group_by { |r| r.class.name }

    conditions = by_type.map do |type, reviewers|
      sanitize_sql_for_conditions(["reviewer_type = ? AND reviewer_id = ?", type, reviewers])
    end

    where(conditions.join(" OR "))
  end

  sig { returns(T.untyped) }
  def self.automated
    where(<<~SQL)
      EXISTS (
        SELECT 1 FROM review_request_reasons
        WHERE
          review_request_reasons.review_request_id = review_requests.id
      )
    SQL
  end

  sig { returns(T.untyped) }
  def self.users
    user_ids = where(reviewer_type: "User").pluck(:reviewer_id)
    return User.none if user_ids.empty?
    User.where(id: user_ids)
  end

  sig { returns(T.untyped) }
  def self.teams
    team_ids = where(reviewer_type: "Team").pluck(:reviewer_id)
    return Team.none if team_ids.empty?
    Team.where(id: team_ids)
  end

  sig { returns(T::Array[T.any(User, Team)]) }
  def self.reviewers
    user_reqs, team_reqs = pluck(:reviewer_type, :reviewer_id).partition { |request| request.first == "User" }

    user_ids = user_reqs.map(&:last)
    team_ids = team_reqs.map(&:last)

    [].tap do |reviewers|
      reviewers.concat User.where(id: user_ids) if user_ids.any?
      reviewers.concat Team.where(id: team_ids) if team_ids.any?
    end
  end

  sig { returns(T.untyped) }
  def self.pending
    where(<<-SQL)
      NOT EXISTS (
          SELECT 1 FROM pull_request_reviews_review_requests
          WHERE pull_request_reviews_review_requests.review_request_id = review_requests.id
        )
    SQL
  end

  sig { returns(T.untyped) }
  def self.fulfilled
    where(<<-SQL)
      EXISTS (
          SELECT 1 FROM pull_request_reviews_review_requests
          WHERE pull_request_reviews_review_requests.review_request_id = review_requests.id
        )
    SQL
  end

  # Public: Marks a deferred request as ready and triggers appropriate actions.
  #
  # Returns early if the request has been dismissed or has been fulfilled.
  #
  # Will trigger the creation of a review_requested issue event and its related
  # notifications and subscriptions. Will trigger team review request delegation
  # if configured. Sets the deferred property to false.
  sig { params(user: User).void }
  def ready!(user:)
    update(deferred: false)

    return if dismissed?
    return unless pending?

    transaction do
      trigger_review_requested_event(actor: user)
      delegate_to_members
    end
  end

  # checks to see if the review request  is a spammy user
  # checks to see if the viewer can view the team request
  sig { params(viewer: T.nilable(User)).returns(Promises::Boolean) }
  def async_visible_subject_for(viewer)
    return Promise.resolve(true) if viewer && viewer.site_admin?
    return Promise.resolve(true) unless GitHub.spamminess_check_enabled?

    self.async_reviewer.then do |reviewer|
      if reviewer.is_a?(::Team)
        reviewer.async_visible_to?(viewer).then do |visible|
          visible
        end
      elsif reviewer
        !reviewer.spammy?
      else
        false
      end
    end
  end

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def visible_subject_for(viewer)
    async_visible_subject_for(viewer).sync
  end

  # Required for GraphQL abilities loader.
  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def hide_from_user?(viewer)
    false
  end

  sig { returns(T::Boolean) }
  def pending?
    self.pull_request_reviews.empty?
  end

  sig { void }
  def notify_pull_request_socket_subscribers
    if T.must(pull_request).repository&.feature_enabled?(:reviewers_event_updates)
      T.must(pull_request).notify_socket_subscribers(associated_updates: { "#{LIVE_UPDATE_EVENT_NAME}": true })
    else
      T.must(pull_request).notify_socket_subscribers
    end
  end

  sig { void }
  def synchronize_search_index
    T.must(pull_request).synchronize_search_index
  end

  sig { params(actor: T.nilable(User)).void }
  def trigger_review_requested_event(actor: nil)
    T.must(pull_request).trigger_review_requested_event(self, actor:)
  end

  def dismiss(via_assignment: false)
    self.dismissed_via_assignment = via_assignment
    self.dismissed_at ||= Time.current
  end

  sig { returns(T::Boolean) }
  def dismissed?
    dismissed_at?
  end

  sig { returns(T::Boolean) }
  def recently_dismissed?
    dismissed? && saved_change_to_dismissed_at?
  end

  # Only trigger an request_remove event if the issue is still around.
  # We don't want this to fire when the request is being destroyed
  # as a result of an issue being destroyed.
  sig { void }
  def trigger_review_request_removed_event
    return unless pull_request = self.pull_request
    return unless reviewer = self.reviewer
    pull_request.trigger_review_request_removed_event(reviewer)
  end

  sig { void }
  def ensure_requested_reviewer_is_a_collaborator
    return if reviewer.is_a?(Bot)
    return if reviewer.is_a?(User) && reviewer.ghost?

    if T.must(pull_request).user == reviewer
      errors.add :reviewer, "cannot be PR author"
    elsif !T.must(pull_request).can_request_review_from?(reviewer)
      errors.add :reviewer, "must be a collaborator"
    end
  end

  sig { void }
  def ensure_requested_team_is_in_valid_org
    return if reviewer.is_a?(User)

    pull_request = T.must(self.pull_request)
    repository = T.must(pull_request.repository)

    if !repository.in_organization?
      errors.add :reviewer, "must be in an organization"
    elsif repository.organization != reviewer.organization
      errors.add :reviewer, "must be in same organization"
    end
  end

  sig { void }
  def one_pending_request_per_reviewer_and_pull_request
    dupes = self.class.pending.not_dismissed.where \
      pull_request_id: pull_request_id,
      reviewer_id: reviewer_id,
      reviewer_type: reviewer_type
    dupes = dupes.where("id <> ?", id) if persisted?
    if dupes.exists?
      errors.add :reviewer, "can only have one pending request per pull request"
    end
  end

  # Public: Builds new reason objects.
  #
  # by_type   - A Hash of reasons grouped by their type.
  #
  # Example
  #
  #   request.reasons_by_type = {
  #     codeowners: [{tree_oid: "0123456", path: "CODEOWNERS", line: 42, pattern: "*"}]
  #   }
  #   => <#ReviewRequestReason codeowners_tree_oid: "0123456", codeowners_path: "CODEOWNERS" …>
  sig { params(by_type: Hash).void }
  def reasons_by_type=(by_type)
    by_type.each do |type, reasons_array|
      reasons_array.each do |reason_attributes|
        typed_attrs = reason_attributes.reduce({}) do |coll, (attr, value)|
          coll.merge "#{type}_#{attr}" => value
        end

        reasons.build(typed_attrs)
      end
    end
  end

  batch_method(:prelude_visible_assigned_from_team_name) do |review_requests, viewer|
    review_requests = T.let(review_requests, T::Array[ReviewRequest])
    results = Promise.all(review_requests.map do |review_request|
      review_request.async_assigned_from_review_request.then do |team_request|
        next unless team_request

        team_request.async_reviewer.then do |team|
          next unless team.is_a?(::Team)

          team.async_visible_to?(viewer).then do |visible|
            next unless visible

            team.async_organization.then do |org|
              next unless org
              team.to_s
            end
          end
        end
      end
    end).sync

    review_requests.zip(results).to_h
  end

  sig { returns(Promise[T.nilable(ReviewRequestReason)]) }
  def async_codeowner_reason
    return @async_codeowner_reason if defined?(@async_codeowner_reason)

    @async_codeowner_reason = T.let(async_reasons, Promise[T::Array[ReviewRequestReason]]).then do |reasons|
      reasons.find(&:codeowners?)
    end
  end

  sig { returns(Promises::Boolean) }
  def async_as_codeowner?
    async_codeowner_reason.then(&:present?)
  end

  sig { returns(Promise[T.nilable(String)]) }
  def async_codeowners_path_uri
    async_codeowner_reason.then do |reason|
      reason&.async_codeowners_path_uri
    end
  end

  sig { returns(Promise[T.untyped]) }
  def async_codeowners_file
    @async_codeowners_file ||= async_codeowner_reason.then do |reason|
      reason&.async_codeowners_file
    end
  end

  private

  sig { void }
  def set_repository_id
    self.repository_id = pull_request&.repository_id
  end

  sig { void }
  def notify_state_changed
    channel = GitHub::WebSocket::Channels.pull_request_review_state(pull_request)
    pull_request = T.must(self.pull_request)

    GitHub::WebSocket.notify_repository_channel(pull_request.repository, channel, {
      wait: pull_request.default_live_updates_wait,
      pull_request_id: pull_request.id,
    })
  end

  # Perform review request delegation if this review request targets a Team and
  # the team has enabled the setting.
  sig { void }
  def delegate_to_members
    return unless reviewer.is_a?(Team)
    pull_request = T.must(self.pull_request)

    if reviewer.review_request_delegation_enabled?
      issue = T.must(pull_request.issue)
      result = Team::ReviewRequestDelegation.delegate_to_members(
        actor: issue.modifying_user,
        pull_request: pull_request,
        team: reviewer,
        strategy: reviewer.review_request_delegation_algorithm.to_sym,
        max_auto_assigned_reviewers_count: reviewer.review_request_delegation_member_count,
        remove_team_request: reviewer.review_request_delegation_remove_team_request,
        include_child_team_members: reviewer.review_request_delegation_include_child_team_members,
        count_existing_reviewers: reviewer.review_request_delegation_count_members_already_requested,
      )

      if !result.success? && !reviewer.review_request_delegation_notify_team?
        issue.subscribe_all(issue.subscribable_team_members(reviewer), "review_requested")
      end
    end
  end
end
