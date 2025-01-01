# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectsV2StatusUpdatePayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user, login: "actor")
    @org = create(:organization)
    @project = create(:memex_project, owner: @org)
    @status_update = create(:memex_project_status, memex_project: @project)
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :created, memex_project_status: @status_update, actor: @actor, changes: nil)
    Hook::Event::ProjectsV2StatusUpdateEvent.new(
      action: action,
      memex_project_status_id: memex_project_status.id,
      actor_id: actor.id,
      org_id: @org.id,
      changes: changes
    )
  end

  private def serialize_event(event)
    Hook::Payload::ProjectsV2StatusUpdatePayload.new(event).to_hash
  end

  test "serializes a created event payload" do
    payload = serialize_event(create_event)
    assert_equal :created, payload[:action]
    assert_equal @status_update.id, payload[:projects_v2_status_update][:id]
  end

  test "serializes changes" do
    payload = serialize_event(create_event(action: :edited, changes: { "body" => %w[old new] }))
    expected_changes = {
      body: {
        from: "old",
        to: "new",
      }
    }

    assert_equal :edited, payload[:action]
    assert_equal @status_update.id, payload[:projects_v2_status_update][:id]
    assert_equal expected_changes, payload[:changes]
  end
end
