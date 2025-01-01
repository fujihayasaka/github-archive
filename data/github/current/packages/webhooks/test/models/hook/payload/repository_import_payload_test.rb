# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadRepositoryImportPayloadTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @actor = create(:user, login: "user")
    @status = "success"
  end

  context "when a repository import is created" do
    test "v3" do
      event = Hook::Event::RepositoryImportEvent.new(
        status:        @status,
        repository_id: @repo.id,
        actor_id:      @actor.id,
      )

      payload = Hook::Payload::RepositoryImportPayload.new(event)
      v3 = payload.to_hash

      assert_equal @status, v3[:status]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @actor.id, v3[:sender][:id]
    end
  end
end
