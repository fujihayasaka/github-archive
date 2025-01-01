# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class HiddenUserTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    context ".hide_user" do
      test "creates a hidden_users entry" do
        Timecop.freeze do
          HiddenUser.hide_user(@user.id)

          assert_equal 1, HiddenUser.count
          assert hidden_user = HiddenUser.first
          assert_equal @user.id, T.must(hidden_user).user_id
          assert_equal Time.now.to_i, T.must(hidden_user).created_at.to_i
        end
      end

      test "ignores duplicates" do
        HiddenUser.hide_user(@user.id)

        assert_equal 1, HiddenUser.count

        HiddenUser.hide_user(@user.id)

        assert_equal 1, HiddenUser.count
        assert hidden_user = HiddenUser.first
        assert_equal @user.id, T.must(hidden_user).user_id
      end
    end

    context ".unhide_user" do
      test "removes the hidden_users entry" do
        HiddenUser.hide_user(@user.id)
        another_user = create(:user)
        HiddenUser.hide_user(another_user.id)

        refute_empty HiddenUser.where(user_id: @user.id)
        refute_empty HiddenUser.where(user_id: another_user.id)

        HiddenUser.unhide_user(@user.id)

        assert_empty HiddenUser.where(user_id: @user.id)
        refute_empty HiddenUser.where(user_id: another_user.id)
      end

      test "does not remove multiple entries" do
        HiddenUser.hide_user(@user.id)
        another_user = create(:user)
        HiddenUser.hide_user(another_user.id)

        refute_empty HiddenUser.where(user_id: @user.id)
        refute_empty HiddenUser.where(user_id: another_user.id)

        assert_raises(ArgumentError, "user_id must be numeric") do
          HiddenUser.unhide_user([@user.id, another_user.id])
        end

        refute_empty HiddenUser.where(user_id: @user.id)
        refute_empty HiddenUser.where(user_id: another_user.id)
      end
    end
  end
end
