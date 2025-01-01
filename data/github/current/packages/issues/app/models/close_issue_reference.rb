# typed: true
# frozen_string_literal: true

class CloseIssueReference < ApplicationRecord::Collab
  include Instrumentation::Model
  include GitHub::BatchedScope

  MAX_MANUAL_REFERENCES = 10

  belongs_to :issue
  belongs_to :pull_request
  belongs_to :pull_request_author, class_name: "User"
  belongs_to :issue_repository, class_name: "Repository"
  destroy_in_background_with :issue_repository

  enum :source, [:xref, :manual]

  before_validation :set_issue_repository
  before_validation :set_pull_request_author
  before_validation :set_actor_id

  after_commit :create_connected_events, on: :create, if: :manual? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :create_disconnected_events, on: :destroy, if: :manual? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: [:create, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_issue_and_pr_search_index, on: [:create, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates :issue, :pull_request, :pull_request_author, :issue_repository, presence: true
  validates :issue_id, uniqueness: { scope: :pull_request_id }
  validate :pull_request_must_reference_issue
  validate :max_manual_xrefs, on: :create
  validate :actor_has_xref_permission

  scope :closes, ->(issue) { where(issue_id: issue) }

  scope :by_user, ->(user) { where(actor_id: user) }

  def self.possible_closing_references_for(issue_or_pr:, viewer:, limit:, repository:)
    connected_by_key = issue_or_pr.is_a?(PullRequest) ? :issue_id : :pull_request_id

    existing_ids = issue_or_pr.close_issue_references.pluck(connected_by_key)
    possible_references_from_repo = possible_repository_closing_reference_ids(issue_or_pr: issue_or_pr,
      limit: limit,
      viewer: viewer,
      repository: repository)
    possible_references_for_user = possible_involved_closing_reference_ids_for(issue_or_pr: issue_or_pr,
      viewer: viewer,
      repository: repository)

    ids = (possible_references_for_user + possible_references_from_repo - existing_ids).uniq.first(limit)

    scope = issue_or_pr.is_a?(PullRequest) ? Issue : PullRequest

    return scope.none unless ids.any?

    result = scope.where(id: ids).to_a
    result.sort_by do |row|
      ids.index(row.id)
    end
  end

  # Find recent issues or pull requests from the repository that may be relevant
  # to connect to the source.
  def self.possible_repository_closing_reference_ids(issue_or_pr:, limit:, viewer:, repository:)
    scope = Issue.for_repository(repository)

    if issue_or_pr.is_a?(PullRequest)
      scope = scope.without_pull_requests
      issues_table_column = :id
    else
      scope = scope.with_pull_requests
      issues_table_column = :pull_request_id
    end

    scope = scope.order(state: :desc, updated_at: :desc)
    scope = scope.where.not(user_hidden: 1) unless viewer.site_admin?
    scope.limit(limit)
      .pluck(issues_table_column)
  end

  # Find issues or pull requests that the user is involved with or participating in.
  # See Search::Filters::InvolvesFilter for more details.
  def self.possible_involved_closing_reference_ids_for(issue_or_pr:, viewer:, repository:)
    if issue_or_pr.is_a?(PullRequest)
      search_type = "issue"
      issues_table_column = :id
    else
      search_type = "pr"
      issues_table_column = :pull_request_id
    end

    query = [
      [:involves, viewer.login],
      [:repo, repository.name],
      [:is, search_type],
    ]

    tags = []
    tags << "controller:#{GitHub.context[:controller]}" if GitHub.context[:controller]
    tags << "action:#{GitHub.context[:controller_action]}" if GitHub.context[:controller_action]

    result = Issue::SearchResult.search(
      query:             query,
      prefill_associations: false,
      current_user:      viewer,
      repo:              repository,
      tags:              tags,
      context:           "#{self.name&.demodulize.underscore}-#{__method__}",
    )

    result[:issues].map { |i| i[issues_table_column] }
  end

  def self.viewable_for(viewer:, issue:)
    if issue.pull_request?
      refs = issue.pull_request.close_issue_references.includes(pull_request: [:user, :repository])
      refs.select do |reference|
        issue = reference.issue

        next unless issue
        next if issue.spammy?
        issue.repository.public? || issue.repository.visible_and_readable_by?(viewer)
      end
    else
      refs = issue.close_issue_references.includes(issue: [:user, :repository])
      refs.select do |reference|
        pull_request = reference.pull_request

        next unless pull_request
        next if pull_request.spammy?
        pull_request.repository.public? || pull_request.repository.visible_and_readable_by?(viewer)
      end
    end
  end

  def notify_socket_subscribers
    return unless issue = self.issue

    data = {
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "close issue references updated for issue ##{issue.id}",
    }
    channel = GitHub::WebSocket::Channels.close_issue_references(issue)
    GitHub::WebSocket.notify_issue_channel(issue, channel, data)

    issue.notify_socket_subscribers
    pull_request&.notify_socket_subscribers
  end

  def event_payload
    {
      actor_id: actor_id,
      issue_id: issue_id,
      repository_id: issue_repository_id,
      organization_id: T.must(issue).repository&.organization_id,
    }
  end

  def creator
    pull_request_author
  end

  def creator=(user)
    pull_request_author = user
  end

  private

  def webhook_event_payload_valid?
    issue&.repository&.present?
  end

  def instrument_create
    return unless issue

    actor = User.find_by(id: actor_id)
    return unless actor

    instrument("create") if webhook_event_payload_valid?

    GlobalInstrumenter.instrument("issue.pr_connected", {
      issue_repository: issue&.repository,
      actor: actor,
      issue: issue,
      pull_request: pull_request,
      pull_request_author: pull_request_author,
      source: source,
    })
  end

  def instrument_destroy
    return unless issue&.repository

    actor = User.find_by(id: actor_id)
    return unless actor

    instrument("destroy") if webhook_event_payload_valid?

    GlobalInstrumenter.instrument("issue.pr_disconnected", {
      issue_repository: issue&.repository,
      actor: actor,
      issue: issue,
      pull_request: pull_request,
      pull_request_author: pull_request_author,
      source: source,
    })
  end

  def create_connected_events
    actor = User.find_by(id: actor_id)
    create_issue_and_pr_events(:connected, actor)
  end

  def create_disconnected_events
    actor = User.find_by(id: GitHub.context[:actor_id])
    create_issue_and_pr_events(:disconnected, actor)
  end

  def create_issue_and_pr_events(event_type, actor)
    return unless actor
    return unless pull_request = self.pull_request
    return unless issue = self.issue

    pull_request.issue&.events&.create(event: event_type, actor: actor, subject: issue)
    issue.events.create(event: event_type, actor: actor, subject: pull_request.issue)
  end

  def synchronize_issue_and_pr_search_index
    pull_request&.synchronize_search_index
    issue&.synchronize_search_index
  end

  def set_issue_repository
    self.issue_repository = issue&.repository
  end

  def set_pull_request_author
    user = pull_request&.user
    self.pull_request_author = user unless user&.spammy
  end

  def set_actor_id
    self.actor_id ||= GitHub.context[:actor_id]
  end

  def pull_request_must_reference_issue
    return unless pull_request
    return unless issue = self.issue
    return if !issue.pull_request?

    errors.add(:issue_id, "must not be a pull request")
  end

  def max_manual_xrefs
    return unless pull_request = self.pull_request
    return unless issue = self.issue

    errors.add(:pull_request_id, "exceeds manual reference limit") if pull_request.close_issue_references.manual.count >= MAX_MANUAL_REFERENCES

    errors.add(:issue_id, "exceeds manual reference limit") if issue.close_issue_references.manual.count >= MAX_MANUAL_REFERENCES
  end

  def actor_has_xref_permission
    return unless pull_request && issue

    unless creator = User.find_by(id: actor_id)
      errors.add(:actor_id, "must be present")
      return
    end

    # A mannequin will be the reference creator only during an import (migration) context. Since
    # mannequins do not have any permissions, we need to short circuit this method's permission checks.
    # The check below is an added safeguard in the event these references are created in a context
    # other than an import in the future.
    if creator.mannequin?
      return if creator.owner == issue_repository&.owner
      errors.add(:actor_id, :inaccessible, message: "must be part of the repository's organization")
    end

    if creator_blocked_by_content_author?(creator) ||
      content_author_blocked_by_creator?(creator) ||
      !creator_can_read_target_content?(creator)
      errors.add(:actor_id, :inaccessible, message: "must have access to both issue and pull request")
    end
  end

  def content_author_blocked_by_creator?(creator)
    T.must(issue).user&.blocked_by?(creator) || T.must(pull_request).user&.blocked_by?(creator)
  end

  def creator_blocked_by_content_author?(creator)
    creator.blocked_by?(T.must(issue).user) || creator.blocked_by?(T.must(pull_request).user)
  end

  def creator_can_read_target_content?(creator)
    T.must(issue).readable_by?(creator) && T.must(pull_request).readable_by?(creator)
  end
end
