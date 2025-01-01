# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadReleasePayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple

    # Contains tags 'v1' and 'v2'

    @release = create :release, repository: @repo, author: @user, tag_name: "v1"
  end

  test "v3 structure for published action" do
    event   = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
    payload = Hook::Payload::ReleasePayload.new event

    v3 = payload.to_hash

    assert_equal :published, v3[:action]
    assert_equal @release.id, v3[:release][:id]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end

  test "v3 structure for edited action" do
    changes = { old_body: "v1", make_latest: true }
    event   = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: changes
    payload = Hook::Payload::ReleasePayload.new event

    v3 = payload.to_hash

    assert_equal :edited, v3[:action]
    assert_equal @release.id, v3[:release][:id]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
    assert_equal "v1", v3[:changes][:body][:from]
    assert_equal true, v3[:changes][:make_latest][:to]
  end
end
