# typed: true
# frozen_string_literal: true

require "test_helper"

class MockViewFilter
  def initialize(allow)
    @allow = allow
  end

  def authorized?(**kwargs)
    @allow
  end
end

class GistsShowPageViewTest < GitHub::TestCase
  fixtures do
    @emu = create(:emu) unless GitHub.enterprise?
    @user = create(:user)

    @gist = GistHelpers.generate(user: @staff_user, contents: contents)
  end

  context "show_social_functions?" do
    test "returns false for emus", skip_enterprise: true do
      view = Gists::ShowPageView.new(gist: @gist, current_user: @emu, cap_view_filter: MockViewFilter.new(false))

      assert_equal false, view.show_social_functions?
    end

    test "returns true for non-emus" do
      view = Gists::ShowPageView.new(gist: @gist, current_user: @user, cap_view_filter: MockViewFilter.new(true))

      assert_equal true, view.show_social_functions?
    end
  end

  context "available dangerous actions" do
    test "only the author can edit, delete a gist" do
      anon_gist = GistHelpers.generate(contents: contents)
      user_gist = GistHelpers.generate(user: @user, contents: contents)

      staff_user = create(:staff_admin_user)

      view = Gists::ShowPageView.new(gist: user_gist, current_user: @user, cap_view_filter: MockViewFilter.new(true))
      assert_equal true, view.show_edit_link?
      assert_equal true, view.show_delete_link?

      view = Gists::ShowPageView.new(
        gist: user_gist,
        current_user: staff_user,
        cap_view_filter: MockViewFilter.new(true),
        anonymous_user_is_creator: false
      )
      assert_equal false, view.show_edit_link?
      assert_equal false, view.show_delete_link?

      # anon users can delete, but not edit a gist
      view = Gists::ShowPageView.new(
        gist: anon_gist,
        cap_view_filter: MockViewFilter.new(true),
        anonymous_user_is_creator: true
      )
      assert_equal false, view.show_edit_link?
      assert_equal true, view.show_delete_link?
    end
  end

  def contents
    [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]
  end
end
