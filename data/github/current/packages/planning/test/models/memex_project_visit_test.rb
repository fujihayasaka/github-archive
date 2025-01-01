# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectVisitTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
    @other_user = create(:verified_user).tap { |u| @org.add_member(u) }

    @memex = create(:memex_project, owner: @org)
    @other_memex = create(:memex_project, owner: @org)
  end

  test "it requires a viewer" do
    visit = MemexProjectVisit.create
    assert_not visit.valid?
    assert_includes visit.errors.full_messages, "Viewer can't be blank"
    assert_includes visit.errors.full_messages, "Memex project can't be blank"
    assert_includes visit.errors.full_messages, "Owner can't be blank"
    assert_includes visit.errors.full_messages, "Last visited at can't be blank"
  end

  test "it requires a unique viewer and memex project" do
    first_visit = MemexProjectVisit.create(memex_project: @memex, owner: @org, viewer: @user, last_visited_at: Time.now.utc)
    assert first_visit.valid?

    second_visit = MemexProjectVisit.create(memex_project: @memex, owner: @org, viewer: @user, last_visited_at: Time.now.utc)
    refute second_visit.valid?

    assert_includes second_visit.errors.full_messages, "Memex project visit already exists for viewer and project"
  end

  test "it allows multiple users to view the same project" do
    first_visit = MemexProjectVisit.create(memex_project: @memex, owner: @org, viewer: @user, last_visited_at: Time.now.utc)
    assert first_visit.valid?

    second_visit = MemexProjectVisit.create(memex_project: @memex, owner: @org, viewer: @other_user, last_visited_at: Time.now.utc)
    assert second_visit.valid?
  end

  test "it allows multiple projects to be viewed by the same user" do
    first_visit = MemexProjectVisit.create(memex_project: @memex, owner: @org, viewer: @user, last_visited_at: Time.now.utc)
    assert first_visit.valid?

    second_visit = MemexProjectVisit.create(memex_project: @other_memex, owner: @org, viewer: @user, last_visited_at: Time.now.utc)
    assert second_visit.valid?
  end
end
