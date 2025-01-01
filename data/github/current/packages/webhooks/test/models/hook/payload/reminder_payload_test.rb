# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadReminderPayloadTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :org_owned)
    @pull_request1 = create(:pull_request, :disable_disk_access, repository: @repo)
    @org = @repo.organization
    @owner = @org.admin
    make_trusted_oauth_apps_owner
    @slack_integration = create(:slack_integration)
    @slack_installation = make_integration_installation(
      integration: @slack_integration,
      target: @org,
    )
    @reminder = create(:reminder, remindable: @org, user: @org.admin)
    @personal_reminder = create(:personal_reminder, remindable: @org)
  end

  def payload(options = {})
    event = Hook::Event::ReminderEvent.new(**T.unsafe({
      action: "schedule",
      event_at: Time.current,
      pull_request_ids: [@pull_request1.id],
      repository_id: @repo.id,
    }.merge(options)))
    Hook::Payload::ReminderPayload.new(event)
  end

  context "reminders" do
    test "v3 with a hook installed for a Repository" do
      reminder_payload = payload(reminder_id: @reminder.id)
      v3 = reminder_payload.to_hash
      assert_equal "schedule", v3[:action]
      assert_equal @reminder.id, v3[:reminder][:id]
      assert_equal 1, v3[:pull_requests].size
      assert_nil v3[:user]
    end
  end

  context "personal reminders" do
    test "v3 with a hook installed for a Repository" do
      personal_payload = payload(reminder_id: @personal_reminder.id, personal: true)
      v3 = personal_payload.to_hash
      assert_equal "schedule", v3[:action]
      assert_equal @personal_reminder.id, v3[:reminder][:id]
      assert_equal 1, v3[:pull_requests].size
    end
  end

  test "generates :deleted event payload" do
    GitHub.context.push(actor_id: @owner.id)
    reminder = create(:reminder, remindable: @org, user: @org.admin)
    reminder.set_repository_id_for_reminder_to_delete(@repo.id)
    event = Hook::Event::ReminderEvent.new({
      reminder_id: reminder.id,
      action: "deleted",
      actor_id: @owner.id,
      event_at: Time.zone.now,
      repository_id: @repo.id
    })
    payload = Hook::Payload::ReminderPayload.new(event).to_hash

    assert_equal "deleted", payload[:action]
    assert_equal @owner.id, payload[:sender][:id]
    assert_equal @org.id, payload[:organization][:id]
  end

  test "includes context" do
    reminder_payload = payload(reminder_id: @reminder.id, reminder_event_type: "pull_request_opened", reminder_event_context: { foo: 1 })
    assert_equal({ "foo" => 1, "event" => "pull_request_opened" }, reminder_payload.to_hash[:context])
  end

  test "includes event_at" do
    now = Time.zone.now
    reminder_payload = payload(reminder_id: @reminder.id, event_at: now)
    assert_equal now.getutc.iso8601, reminder_payload.to_hash[:event_at]
  end
end
