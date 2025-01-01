# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::IssueEventAdapter < Issue::Adapter::TimelineEventAdapter
  attr_reader :issue_event
  attr_reader :id
  # PerformableViaApp
  attr_reader :via_app

  def initialize(context, event_id:)
    @issue_event = context.events_by_id[event_id]

    # When rendered from app/views/timeline/_item.html.erb we require an "id" here which
    # matches the graphql id of the event
    @id = @issue_event.global_relay_id
    app = context.integrations_by_model[@issue_event]

    # the `32` size comes from app/views/issues/events/_via_app.html.erb where the gql fragment has `logoUrl(size: 32)`
    @via_app = Issue::Adapter::AppAdapter.new(context, app: app, logo_url_size: 32) if app
  end
end
