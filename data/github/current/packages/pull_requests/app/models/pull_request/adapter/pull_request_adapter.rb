# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::PullRequestAdapter < Issue::Adapter::IssueAdapter
  TYPES = ([
    PlatformTypes::PullRequest,
  ] + Issue::Adapter::IssueAdapter::TYPES).freeze

  attr_reader :pull_request_number, :timeline_loader, :viewer, :pull_request_global_relay_id, :id

  def initialize(context, timeline_loader: nil)
    super(
      context,
      timeline_loader: timeline_loader
    )

    @state_websocket = GitHub::WebSocket::Channels.pull_request_state(context.pull_request)
    @timeline_websocket = GitHub::WebSocket::Channels.pull_request_timeline(context.pull_request)
    @websocket = GitHub::WebSocket::Channels.pull_request(context.pull_request)
    @timeline_loader = timeline_loader
    @pull_request_number = context.pull_request.number
    @pull_request_global_relay_id = @id = context.pull_request.global_relay_id
    @viewer = context.viewer
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
