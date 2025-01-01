# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectsV2ItemPayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user, login: "actor")
    @org = create(:organization)
    @item = create(:memex_project_item, memex_project: create(:memex_project, owner: @org), priority: 500)
    @other_item = create(:memex_project_item, memex_project: create(:memex_project, owner: @org), priority: 1000)
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :edited, item: @item, actor: @actor)
    Hook::Event::ProjectsV2ItemEvent.new(
      action: action,
      memex_project_item_id: item.id,
      actor_id: actor.id,
      organization_id: item.memex_project.organization_owner_id,
    )
  end

  private def serialize_event(event)
    Hook::Payload::ProjectsV2ItemPayload.new(event).to_hash
  end

  test "serializes an edited event payload" do
    payload = serialize_event(create_event)
    assert_equal :edited, payload[:action]
    assert_equal @item.id, payload[:projects_v2_item][:id]
  end
end
