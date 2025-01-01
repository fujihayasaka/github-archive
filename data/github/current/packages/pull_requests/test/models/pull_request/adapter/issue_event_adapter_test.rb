# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestIssueEventAdapterTest < GitHub::TestCase
  fixtures do
    @pull_request = create(:pull_request, :disable_disk_access)
    @issue_event = create(:issue_event, event: "deployed")
  end

  setup do
    @context = PullRequest::Adapter::Context.new(
      @pull_request,
      @pull_request.repository,
      @pull_request.repository.owner
    )
    @context.preload_attr(:events_by_id, {
      @issue_event.id => @issue_event
    })
    @context.preload_attr(:integrations_by_model, {})
  end

  test "loads the event from the context" do
    adapter = PullRequest::Adapter::IssueEventAdapter.new(@context, event_id: @issue_event.id)
    assert_equal @issue_event, adapter.issue_event
  end

  test "has an id field which matches the graphql global_relay_id" do
    adapter = PullRequest::Adapter::IssueEventAdapter.new(@context, event_id: @issue_event.id)
    assert_equal @issue_event.global_relay_id, adapter.id
  end

  # At present for the issue timeline to properly handle these events they must inherit from Issue::Adapter::TimelineEventAdapter
  test "is an Issue::Adapter::TimelineEventAdapter" do
    adapter = PullRequest::Adapter::IssueEventAdapter.new(@context, event_id: @issue_event.id)
    assert adapter.is_a?(Issue::Adapter::TimelineEventAdapter)
  end
end
