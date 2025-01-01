# typed: true
# frozen_string_literal: true

require "test_helper"

class Timeline::EntryLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @timeline_client = mock("timeline_client")
    GitHub.stubs(:timeline_api_client).returns(@timeline_client)
  end

  context ".load_entries" do
    test "returns an empty list in case of no data" do
      response = stub(data: nil)
      GitHub.timeline_api_client.stubs(:get).returns(response)

      issue_id = 3
      viewer = create(:user)
      result = ::Timeline::EntryLoader.load_entries(issue_id, viewer)

      assert_equal 0, result.length
    end

    test "returns an empty list in case of an exception" do
      GitHub.timeline_api_client.stubs(:get).throws(StandardError)

      issue_id = 3
      viewer = create(:user)
      result = ::Timeline::EntryLoader.load_entries(issue_id, viewer)

      assert_equal 0, result.length
    end

    test "added_to_project" do
      user = create(:user)
      project = create(:memex_project, owner: user)
      issue_id = 3

      event = stub_added_to_project_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: project.id
      )
      response = stub_timeline_response([event])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user)
      entry = entries.first

      assert_equal project.id, entry.memex_id
      assert_equal user.id, entry.actor_id
      assert_equal event.created_at.seconds, entry.created_at.to_i
      assert_equal event.created_at.nanos, entry.created_at.nsec
    end

    test "removed_from_project" do
      user = create(:user)
      project = create(:memex_project, owner: user)
      issue_id = 3

      event = stub_removed_from_project_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: project.id
      )
      response = stub_timeline_response([event])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user)
      entry = entries.first

      assert_equal project.id, entry.memex_id
      assert_equal user.id, entry.actor_id
      assert_equal event.created_at.seconds, entry.created_at.to_i
      assert_equal event.created_at.nanos, entry.created_at.nsec
    end

    test "project_item_status_changed" do
      user = create(:user)
      project = create(:memex_project, owner: user)
      issue_id = 3

      event = stub_project_item_status_changed_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: project.id
      )
      response = stub_timeline_response([event])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user)
      entry = entries.first

      assert_equal project.id, entry.memex_id
      assert_equal user.id, entry.actor_id
      assert_equal event.created_at.seconds, entry.created_at.to_i
      assert_equal event.created_at.nanos, entry.created_at.nsec
    end

    test "converted_from_draft" do
      user = create(:user)
      project = create(:memex_project, owner: user)
      issue_id = 3

      event = stub_converted_from_draft_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: project.id
      )
      response = stub_timeline_response([event])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user)
      entry = entries.first

      assert_equal project.id, entry.memex_id
      assert_equal user.id, entry.actor_id
      assert_equal event.created_at.seconds, entry.created_at.to_i
      assert_equal event.created_at.nanos, entry.created_at.nsec
    end

    test "discard event when project doesn't exist or soft deleted" do
      user = create(:user)
      project = create(:memex_project, owner: user)
      issue_id = 3
      deleted_project = create(:memex_project, owner: user, deleted_at: Time.now)
      converted_event = stub_converted_from_draft_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: project.id
      )
      event_deleted_project = stub_project_item_status_changed_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: deleted_project.id
      )

      event_invalid_project = stub_project_item_status_changed_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: 9999
      )
      response = stub_timeline_response([converted_event, event_invalid_project, event_deleted_project])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user)
      assert_equal 1, entries.length
    end

    test "respect cap filter" do
      org = create(:organization)
      org_project = create(:memex_project, owner: org)

      user = create(:user)
      user_project = create(:memex_project, owner: user)

      issue_id = 3

      added_to_org_project = stub_added_to_project_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: org_project.id
      )
      added_to_user_project = stub_added_to_project_timeline_entry(
        user_id: user.id,
        issue_id: issue_id,
        project_id: user_project.id
      )
      response = stub_timeline_response([added_to_org_project, added_to_user_project])
      GitHub.timeline_api_client.stubs(:get).returns(response)

      entries = ::Timeline::EntryLoader.load_entries(issue_id, user, cap_filter: cap_authorizing_filter([user_project]))

      assert_equal 1, entries.length
      entry = entries.first

      assert_equal user_project.id, entry.memex_id
    end
  end

  def stub_added_to_project_timeline_entry(issue_id:, user_id:, project_id:)
    actor = Github::Timeline::Entity.new(id: user_id, type: "User")
    parent = Github::Timeline::Entity.new(id: issue_id, type: "Issue")
    subject = Github::Timeline::Entity.new(id: project_id, type: "Project")
    created_at = now_timestamp
    Github::Timeline::TimelineEntry.new(id: "1", actor: actor, parent: parent, type: "AddedToProjectEvent", created_at: created_at, subject: subject)
  end

  def stub_removed_from_project_timeline_entry(issue_id:, user_id:, project_id:)
    actor = Github::Timeline::Entity.new(id: user_id, type: "User")
    parent = Github::Timeline::Entity.new(id: issue_id, type: "Issue")
    subject = Github::Timeline::Entity.new(id: project_id, type: "Project")
    created_at = now_timestamp
    Github::Timeline::TimelineEntry.new(id: "1", actor: actor, parent: parent, type: "RemovedFromProjectEvent", created_at: created_at, subject: subject)
  end

  def stub_project_item_status_changed_timeline_entry(issue_id:, user_id:, project_id:, previous_status: "before", status: "after")
    actor = Github::Timeline::Entity.new(id: user_id, type: "User")
    parent = Github::Timeline::Entity.new(id: issue_id, type: "Issue")
    subject = Github::Timeline::Entity.new(id: project_id, type: "Project")
    previous_status_prop = Github::Timeline::Property.new(key: "previousStatus", value: previous_status)
    status_prop = Github::Timeline::Property.new(key: "status", value: status)
    created_at = now_timestamp
    Github::Timeline::TimelineEntry.new(
      id: "1",
      actor: actor,
      parent: parent,
      type: "ProjectItemStatusChangedEvent",
      created_at: created_at,
      subject: subject,
      properties: [
        previous_status_prop,
        status_prop
      ]
    )
  end

  def stub_converted_from_draft_timeline_entry(issue_id:, user_id:, project_id:)
    actor = Github::Timeline::Entity.new(id: user_id, type: "User")
    parent = Github::Timeline::Entity.new(id: issue_id, type: "Issue")
    subject = Github::Timeline::Entity.new(id: project_id, type: "Project")
    created_at = now_timestamp
    Github::Timeline::TimelineEntry.new(id: "1", actor: actor, parent: parent, type: "ConvertedFromDraftEvent", created_at: created_at, subject: subject)
  end

  def stub_timeline_response(entries)
    timeline_entries = Github::Timeline::Timeline.new(timeline_entries: entries)
    timeline_entries_response = Github::Timeline::GetTimelineResponse.new(timeline: timeline_entries)
    stub(data: timeline_entries_response, error: nil)
  end

  def now_timestamp
    now = Time.now
    Google::Protobuf::Timestamp.new(seconds: now.to_i, nanos: now.nsec)
  end
end
