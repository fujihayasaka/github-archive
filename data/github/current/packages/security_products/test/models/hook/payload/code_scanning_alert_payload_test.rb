# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningAlertPayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @repo = create :repository, from_example: :simple
  end

  test "payload when the alert is nil" do
    event_args = {
      action: :created,
      repository_id: @repo.id,
      actor_id: @actor.id,
      alert_number: 0,
      ref: "master",
      commit_oid: "beef"
    }
    event = Hook::Event::CodeScanningAlertEvent.new(event_args)
    payload = Hook::Payload::CodeScanningAlertPayload.new(event)
    gen_payload = payload.to_hash
    assert_nil gen_payload[:alert]
  end

  test "payload with a new alert created" do
    event_args = {
      action: :created,
      repository_id: @repo.id,
      actor_id: @actor.id,
      alert_number: 4,
      ref: "master",
      commit_oid: "beef",
      result: {
        number: 4,
        most_recent_instance: { ref_name_bytes: "refs/heads/master" },
        rule: {},
        is_fixed: true,
        fixed_at: Google::Protobuf::Timestamp.new(seconds: 123456)
      }
    }
    event = Hook::Event::CodeScanningAlertEvent.new(event_args)
    gen_payload = Hash.new
    payload = Hook::Payload::CodeScanningAlertPayload.new(event)
    gen_payload = payload.to_hash
    assert_equal @repo.id, gen_payload[:repository][:id]
    assert_equal @actor.id, gen_payload[:sender][:id]

    assert_equal :created, gen_payload[:action]
    assert_equal 4, gen_payload[:alert][:number]
    assert_equal "master", gen_payload[:ref]
    assert_equal "beef", gen_payload[:commit_oid]
    assert_equal "fixed", gen_payload[:alert][:state]
    assert_equal "1970-01-02T10:17:36Z", gen_payload[:alert][:fixed_at]
  end
end
