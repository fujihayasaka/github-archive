# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterGistUserSuggesterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @gist = create(:gist)

    @followed_user = create(:user)
    @user.follow @followed_user

    @not_followed_user = create(:user)

    @blockee_user = create(:user)
    @user.follow @blockee_user

    @commenter_user = create(:user)
    create(:gist_comment, gist: @gist, user: @commenter_user)
  end

  setup do
    @suggester = Suggester::GistUserSuggester.new(viewer: @user, gist: @gist)
  end

  context "mentions" do
    test "includes followed users" do
      assert @suggester.mentions.any? { |x| x[:id] == @followed_user.id }
    end

    test "includes gist commenters" do
      assert @suggester.mentions.any? { |x| x[:id] == @commenter_user.id }
    end

    test "includes gist user" do
      assert @suggester.mentions.any? { |x| x[:id] == @gist.user.id }
    end

    test "does not include user who is not followed" do
      refute @suggester.mentions.any? { |x| x[:id] == @not_followed_user.id }
    end

    test "does not include blocked user" do
      assert @suggester.mentions.any? { |x| x[:id] == @blockee_user.id }
      @blockee_user.block(@user)
      refute @suggester.mentions.any? { |x| x[:id] == @blockee_user.id }
    end

    test "does not include the viewer if viewer is the gist author" do
      suggester = Suggester::GistUserSuggester.new(viewer: @gist.user, gist: @gist)
      refute suggester.mentions.any? { |x| x[:id] == @gist.user_id }
    end
  end
end
