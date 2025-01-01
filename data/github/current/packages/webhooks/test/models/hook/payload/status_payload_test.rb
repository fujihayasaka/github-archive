# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadStatusPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :review_comment_source

    @sha = @repo.heads.find("master").target_oid
    @status = create :status, state: "success", creator: @user, repository: @repo,
                          description: "build complete", target_url: "http://example.ly",
                          sha: @sha, context: "a context"
  end

  setup do
    @event = Hook::Event::StatusEvent.new status: @status
    @payload = Hook::Payload::StatusPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @status.id, v3[:id]
    assert_equal @status.created_at.utc.to_datetime.xmlschema, v3[:created_at]
    assert_equal @status.updated_at.utc.to_datetime.xmlschema, v3[:updated_at]

    assert_equal @sha, v3[:sha]
    assert_equal @repo.name_with_owner, v3[:name]
    assert_equal "success", v3[:state]
    assert_match /#{@user.primary_avatar_path}/, v3[:avatar_url]

    branches = @repo.rpc.branch_contains(@sha)
    assert_equal branches.count, v3[:branches].count
    assert_equal "master", v3[:branches][0][:name]

    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @user.id, v3[:sender][:id]
  end

end
