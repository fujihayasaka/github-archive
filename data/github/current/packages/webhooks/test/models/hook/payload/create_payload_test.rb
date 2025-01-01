# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadCreatePayloadTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @pusher = create(:user)
    @repo = create :repository, owner: @owner
  end

  context "when the pusher is known" do
    test "v3" do
      event = Hook::Event::CreateEvent.new repository_id: @repo.id, ref: "refs/tags/v1.0.1", pusher_id: @pusher.id
      payload = Hook::Payload::CreatePayload.new event
      v3 = payload.to_hash

      assert_equal "v1.0.1", v3[:ref]
      assert_equal :tag, v3[:ref_type]
      assert_equal :user, v3[:pusher_type]

      assert_equal "master", v3[:master_branch]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @pusher.id, v3[:sender][:id]
      assert_equal @pusher.login, v3[:sender][:login]
    end
  end

  context "when the pusher is unknown" do
    test "v3" do
      event = Hook::Event::CreateEvent.new repository_id: @repo.id, ref: "refs/heads/mdo/slit-diffs"
      payload = Hook::Payload::CreatePayload.new event
      v3 = payload.to_hash

      assert_equal "mdo/slit-diffs", v3[:ref]
      assert_equal :branch, v3[:ref_type]
      assert_equal :deploy_key, v3[:pusher_type]

      assert_equal "master", v3[:master_branch]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @owner.id, v3[:sender][:id]
      assert_equal @owner.login, v3[:sender][:login]
    end
  end
end
