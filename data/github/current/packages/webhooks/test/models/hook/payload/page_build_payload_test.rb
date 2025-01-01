# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPageBuildPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @repo.create_page
    @build = @repo.page.builds.create!(pusher: @user, status: "built")
  end

  setup do
    @event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
    @payload = Hook::Payload::PageBuildPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @build.id, v3[:id]
    assert_equal "built", v3[:build][:status]

    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @user.id, v3[:sender][:id]
  end

end
