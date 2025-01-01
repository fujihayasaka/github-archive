# typed: true
# frozen_string_literal: true

class Issue::Adapter::ClosedEventAdapter < Issue::Adapter::IssueEventAdapter
  TYPES = [
    PlatformTypes::ClosedEvent
  ].freeze

  EVENT = "ClosedEvent"

  attr_reader :closable
  attr_reader :closer
  attr_reader :state_reason
  attr_reader :message
  attr_reader :pull_request
  attr_reader :column_name
  attr_reader :visible_closer_for

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: EVENT)

    @closable = Issue::Adapter::ClosableAdapter.new(context)
    event = context.events_by_id[event_id]
    closer = event.closer
    @state_reason = event.state_reason&.upcase
    @message = event.message
    @pull_request = context.pull_request if context.respond_to?(:pull_request)
    @column_name = closer.is_a?(MemexProject) ? event.column_name : nil
    return unless closer

    has_visible_closer = if closer.is_a?(MemexProject)
      event.visible_closer_for(context.viewer).present?
    else
      # Only pull requests or issues will have a repository ID as a direct attribute
      # Commit doesn't have it as a direct property, so we need to access it through the repo object.
      repo_id = closer.is_a?(Commit) ? closer.repository.id : closer.repository_id
      context.readable_repositories_by_id.has_key?(repo_id)
    end

    return unless has_visible_closer

    @closer = case closer
    when Commit
      Issue::Adapter::CommitAdapter.new(context, commit: closer)
    when PullRequest
      Issue::Adapter::PullRequestAdapter.new(context, pull_request: closer)
    when Issue
      Issue::Adapter::IssueAdapter.new(context)
    when MemexProject
      Issue::Adapter::MemexProjectAdapter.new(context, project: closer)
    end
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
