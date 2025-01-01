# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsStargazersPageViewTest < GitHub::TestCase
  fixtures do
    @staff_user = create(:staff_admin_user)
    @user = create(:user)
    @spammy_user = create(:user, spammy: true)

    contents = [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]

    @gist = GistHelpers.generate(user: @staff_user, contents: contents)
  end

  context "stargazers" do
    test "return stargazers" do
      @user.star(@gist)

      view = Gists::StargazersPageView.new(gist: @gist, current_user: @user)

      assert view.stargazers.count > 0
    end

    test "doesn't return stargazers when starred by spammy user for users" do
      @spammy_user.star(@gist)

      view = Gists::StargazersPageView.new(gist: @gist, current_user: @user)

      assert view.stargazers.count == 0
    end unless GitHub.enterprise?

    test "doesn't return stargazers when starred by spammy user for nil" do
      @spammy_user.star(@gist)

      view = Gists::StargazersPageView.new(gist: @gist, current_user: nil)

      assert view.stargazers.count == 0
    end unless GitHub.enterprise?

    test "does return stargazers when starred by spammy user for staff" do
      @spammy_user.star(@gist)

      view = Gists::StargazersPageView.new(gist: @gist, current_user: @staff_user)

      assert view.stargazers.count > 0
    end

    test "does return stargazers when starred by spammy user for self" do
      @spammy_user.star(@gist)

      view = Gists::StargazersPageView.new(gist: @gist, current_user: @spammy_user)

      assert view.stargazers.count > 0
    end
  end
end
