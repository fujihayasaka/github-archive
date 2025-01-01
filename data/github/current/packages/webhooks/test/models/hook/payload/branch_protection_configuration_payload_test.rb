# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadBranchProtectionConfigurationPayloadTest < GitHub::TestCase

  fixtures do
    @org = create(:organization, plan: "business_plus")
    @org_repo = create(:repository, owner: @org)
    @actor = @org.admins.first
    @repo = create(:repository, owner: @actor)
  end

  context "org owned repo" do
    [:enabled, :disabled].each do |action|
      context "branch protections #{action}" do
        test "payload" do
          event = Hook::Event::BranchProtectionConfigurationEvent.new action: action, actor_id: @actor.id, repository_id: @org_repo.id
          payload = Hook::Payload::BranchProtectionConfigurationPayload.new(event).to_hash

          assert_equal action, payload[:action]
          assert_equal @org_repo.id, payload[:repository][:id]
          assert_equal @org.id, payload[:organization][:id]
          assert_equal @actor.id, payload[:sender][:id]
        end
      end
    end
  end

  context "user owned repo" do
    [:enabled, :disabled].each do |action|
      context "branch protections #{action}" do
        test "payload" do
          event = Hook::Event::BranchProtectionConfigurationEvent.new action: action, actor_id: @actor.id, repository_id: @repo.id
          payload = Hook::Payload::BranchProtectionConfigurationPayload.new(event).to_hash

          assert_equal action, payload[:action]
          assert_equal @repo.id, payload[:repository][:id]
          assert_nil payload[:organization]
          assert_equal @actor.id, payload[:sender][:id]
        end
      end
    end
  end unless TestEnv.test_with_all_emus?
end
