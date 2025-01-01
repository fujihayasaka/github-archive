# typed: true
# frozen_string_literal: true

require "test_helper"

class GistUsersShowPageViewTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  setup do
    params = {}
    current_page = 2
    pagination_info = GistPaginationInfo.new(params, current_page)
    gists = pagination_info.apply_to_rel(@user.gists.active)
    @view = GistUsers::ShowPageView.new \
      current_page: :all,
      gist: Gist.new,
      gists: gists,
      user: @user,
      viewer: @user,
      sidebar_counts: { forked: 0, starred: 0, all: 0 }
  end

  context "sidebar counts" do
    test "shows the starred tab when there are starred gists" do
      refute @view.show_starred_tab?
      @view.sidebar_counts[:starred] = 5
      assert @view.show_starred_tab?
    end

    test "shows the forked tab when there are forked gists" do
      refute @view.show_forked_tab?
      @view.sidebar_counts[:forked] = 5
      assert @view.show_forked_tab?
    end
  end

  test "public visibility label is correct" do
    assert_equal "Public", @view.visibility_name("public")
  end

  test "scope name returns correct values" do
    assert_equal "gists", @view.scope_name
    assert_equal "public gists", @view.scope_name(shortened: false)
  end
end
