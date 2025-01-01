# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectsV2PayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user, login: "actor")
    @org = create(:organization)
    @project = create(:memex_project, owner: @org)
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :created, project: @project, actor: @actor, changes: nil)
    Hook::Event::ProjectsV2Event.new(
      action: action,
      project_id: project.id,
      actor_id: actor.id,
      org_id: project.organization_owner_id,
      changes: changes
    )
  end

  private def serialize_event(event)
    Hook::Payload::ProjectsV2Payload.new(event).to_hash
  end

  test "serializes an created event payload" do
    payload = serialize_event(create_event)
    assert_equal :created, payload[:action]
    assert_equal @project.id, payload[:projects_v2][:id]
  end

  test "serializes changes" do
    changes = {
      public: [0, 1],
      title: ["My Memex Project", "My Memex Project 2"],
      short_description: ["Short description", "Short description 2"],
      description: ["Description", "Description 2"]
    }
    payload = serialize_event(create_event(action: :edited, changes: changes))

    assert_equal :edited, payload[:action]
    assert_equal @project.id, payload[:projects_v2][:id]
    assert_equal !!changes[:public].first, payload[:changes][:public][:from]
    assert_equal !!changes[:public].second, payload[:changes][:public][:to]
    assert_equal changes[:title].first, payload[:changes][:title][:from]
    assert_equal changes[:title].second, payload[:changes][:title][:to]
    assert_equal changes[:short_description].first, payload[:changes][:short_description][:from]
    assert_equal changes[:short_description].second, payload[:changes][:short_description][:to]
    assert_equal changes[:description].first, payload[:changes][:description][:from]
    assert_equal changes[:description].second, payload[:changes][:description][:to]
  end
end
