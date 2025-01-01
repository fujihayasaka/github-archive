# typed: true
# frozen_string_literal: true

require "test_helper"

class SuppressionListTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email = @user.emails.first
    @email2 = create(:user_email, user: @user)
  end

  context ".add_user" do
    test "marks all of the user's email addresses as suppressed" do
      refute @email.suppressed?
      refute @email2.suppressed?
      SuppressionList.add_user(@user)
      assert @email.reload.suppressed?
      assert @email2.reload.suppressed?
    end

    test "raises an exception if an email can't be suppressed" do
      UserEmail.any_instance.stubs(:mark_as_suppressed!).raises(StandardError)

      assert_raises StandardError do
        SuppressionList.add_user(@user)
      end
    end
  end

  context ".remove_user" do
    test "removes all of the user's email address suppressions" do
      SuppressionList.add_user(@user)
      assert SuppressionList.includes_user?(@user)

      SuppressionList.remove_user(@user)
      refute SuppressionList.includes_user?(@user)
    end
  end

  context ".includes_user?" do
    test "true if a user has any email addresses in the list" do
      SuppressionList.add_user(@user)
      assert SuppressionList.includes_user?(@user)
    end

    test "false otherwise" do
      refute SuppressionList.includes_user?(@user)
    end
  end
end
