# typed: true
# frozen_string_literal: true

require "test_helper"

class GistAssociationsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    gist_owner = create(:user)
    gist_contents = [{ name: "hello.md", value: "wee!" }]
    @gist1 = GistHelpers.generate(user: gist_owner, contents: gist_contents)
    @gist2 = GistHelpers.generate(user: gist_owner, contents: gist_contents)
  end

  test "#starred_gists exclude deleted gists" do
    @user.star(@gist1)
    @user.star(@gist2)

    assert_equal 2, @user.starred_gists.count

    @gist1.destroy

    starred_gists = @user.reload.starred_gists.to_a

    assert_equal 1, starred_gists.count
    assert_equal [@gist2], starred_gists
  end

  test "#gist_forks exclude deleted gists" do
    forked_gist1 = @gist1.fork(@user)
    forked_gist2 = @gist2.fork(@user)

    assert_equal 2, @user.gist_forks.count

    forked_gist1.destroy

    gist_forks = @user.reload.gist_forks.to_a

    assert_equal 1, gist_forks.count
    assert_equal [forked_gist2], gist_forks
  end
end
