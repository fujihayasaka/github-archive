# typed: true
# frozen_string_literal: true

class Issue::Adapter::ReferencedEventAdapter < Issue::Adapter::IssueEventAdapter
  REFERENCED_EVENT = "ReferencedEvent"

  attr_reader :id, :commit_id, :subject, :commit, :actor, :created_at
  attr_reader :via_app

  TYPES = [
    PlatformTypes::ReferencedEvent,
  ].freeze

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: REFERENCED_EVENT)

    event = context.events_by_id[event_id]
    @event_commit = event.commit
    issue = context.issue

    @id = event.global_relay_id
    @created_at = event.created_at

    @commit_id = event.commit_id
    @has_closed_subject = issue.closed_by_commit_oids.include?(event.commit_id)
    @subject = Issue::Adapter::ReferencedIssueAdapter.new(context, issue: issue)

    @actor = context.users_by_id[event.actor_id]
    @commit = Issue::Adapter::ReferencedCommitAdapter.new(context, commit: @event_commit) if @event_commit
    @is_direct_reference = event.direct_reference?

    @is_authored_by_pusher = false
    unless @event_commit.nil?
      @is_authored_by_pusher = @event_commit.author_actors.any? { |actor| actor.actor.present? && actor.actor.id == event.actor_id }
    end

    @will_close_subject = event.will_close_subject
    @is_cross_repository = event.cross_commit_repository?

    @has_closed_subject = false
    if commit?
      @has_closed_subject = issue.closed_by_commit_oids.include?(@commit_id)
    end
  end

  def commit?
    !!@event_commit
  end

  def will_close_subject?
    @will_close_subject
  end

  def is_direct_reference?
    @is_direct_reference
  end

  def is_authored_by_pusher?
    @is_authored_by_pusher
  end

  def is_cross_repository?
    @is_cross_repository
  end

  def has_closed_subject?
    @has_closed_subject
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
