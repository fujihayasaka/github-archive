# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterUserSuggesterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)

    @followed_user = create(:user)
    @user.follow @followed_user

    @not_followed_user = create(:user)

    @blockee_user = create(:user)
    @user.follow @blockee_user
  end

  setup do
    @suggester = Suggester::UserSuggester.new(viewer: @user, cap_filter: cap_authorizing_filter)
  end

  context "mentions" do
    test "includes followed users" do
      assert @suggester.mentions.any? { |x| x[:id] == @followed_user.id }
    end

    test "does not include user who is not followed" do
      refute @suggester.mentions.any? { |x| x[:id] == @not_followed_user.id }
    end

    test "does not include blocked user" do
      assert @suggester.mentions.any? { |x| x[:id] == @blockee_user.id }
      @blockee_user.block(@user)
      refute @suggester.mentions.any? { |x| x[:id] == @blockee_user.id }
    end
  end
end
