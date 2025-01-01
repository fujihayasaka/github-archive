# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityAndAnalysisPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user, login: "github")
    @repo = create(:private_repository, owner: @org)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
    @changes = {
      from: {
        security_and_analysis: Api::Serializer.serialize(:security_and_analysis_hash, @repo)
      }
    }

    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
  end

  test "payload for changes" do
    event_args = {
      repository_id: @repo.id,
      actor_id: @user.id,
      changes: @changes
    }

    event = Hook::Event::SecurityAndAnalysisEvent.new(event_args)
    payload = Hook::Payload::SecurityAndAnalysisPayload.new(event)

    payload_hash = payload.to_hash
    changes_payload = payload_hash[:changes][:from][:security_and_analysis]
    repo_payload = payload_hash[:repository][:security_and_analysis]

    assert_equal "enabled", changes_payload[:advanced_security][:status]
    assert_equal "disabled", changes_payload[:secret_scanning][:status]
    assert_equal "disabled", changes_payload[:secret_scanning_push_protection][:status]

    assert_equal "enabled", repo_payload[:advanced_security][:status]
    assert_equal "enabled", repo_payload[:secret_scanning][:status]
    assert_equal "disabled", repo_payload[:secret_scanning_push_protection][:status]
  end
end
