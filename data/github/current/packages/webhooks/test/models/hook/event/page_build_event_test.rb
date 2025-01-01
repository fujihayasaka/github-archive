# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPageBuildEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @repo.create_page
    @build = @repo.page.builds.create!(pusher: @user, status: "built")
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::PageBuildEvent, :page_build_id
  end

  context "#page_build" do
    test "returns the specified page build" do
      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      assert_equal @build, event.page_build
    end
  end

  context "#target_repository" do
    test "returns the repository of specified page build" do
      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil if the page of specified page build" do
      @build.page.delete
      refute @build.reload.page

      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the user who pushed the specified page build" do
      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      assert_equal @user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true if we can find the page for the page_build" do
      assert @build.page

      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      assert event.deliverable?
    end

    test "returns false if we cannot find the page for the page_build" do
      @build.page.delete
      refute @build.reload.page

      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      refute event.deliverable?
    end

    test "returns false if we cannot find the repository for the page_build" do
      @repo.delete
      refute @build.reload.repository

      event = Hook::Event::PageBuildEvent.new page_build_id: @build.id
      refute event.deliverable?
    end
  end
end
