# typed: true
# frozen_string_literal: true

class Issue::Adapter::IssueEventAdapter < Issue::Adapter::TimelineEventAdapter
  attr_reader :database_id
  attr_reader :id
  attr_reader :created_at
  attr_reader :actor

  # PerformableViaApp
  attr_reader :via_app

  delegate :automated?, to: :@issue_event

  def initialize(context, event_id:, event_name:)
    super(context)

    @database_id = event_id
    @event_name = event_name

    @issue_event = context.events_by_id[event_id]
    @id = @issue_event.global_relay_id
    @created_at = @issue_event.created_at

    app = context.integrations_by_model[@issue_event]

    # the `32` size comes from app/views/issues/events/_via_app.html.erb where the gql fragment has `logoUrl(size: 32)`
    @via_app = Issue::Adapter::AppAdapter.new(context, app: app, logo_url_size: 32) if app

    @actor = @issue_event.event_actor(viewer: @context.viewer)
  end

  def event_name
    @event_name.chomp("Event").underscore
  end
end
