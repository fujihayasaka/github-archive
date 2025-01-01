# typed: true
# frozen_string_literal: true

require "test_helper"

class UserGeneratedContentTest < GitHub::TestCase
  spammy_only

  fixtures do
    @user = create(:user)
    create(:issue, user: @user)
  end

  context "has_recently_updated_content_on_any_table?" do
    test "happy path" do
      assert Spam::UserGeneratedContent.has_recently_updated_content_on_any_table?([:issues, :issue_comments], @user.id)
      refute Spam::UserGeneratedContent.has_recently_updated_content_on_any_table?([:issue_comments], @user.id)
    end
  end

  context "has_recently_updated_content?" do
    test "happy path" do
      assert Spam::UserGeneratedContent.has_recently_updated_content?(:issues, @user.id)
      refute Spam::UserGeneratedContent.has_recently_updated_content?(:issue_comments, @user.id)
    end

    test "returns false for ignored tables" do
      refute Spam::UserGeneratedContent.has_recently_updated_content?(:followers, @user.id)
      refute Spam::UserGeneratedContent.has_recently_updated_content?(:workflow_runs, @user.id)
    end

    test "returns false if klass can't be found" do
      refute Spam::UserGeneratedContent.has_recently_updated_content?(:rocket_ships, @user.id)
    end

    test "respects since parameter" do
      Timecop.freeze do
        create(:issue_comment, user: @user)
        Timecop.travel(2.minutes) do
          refute Spam::UserGeneratedContent.has_recently_updated_content?(:issue_comments, @user.id, since: 1.minute)
          assert Spam::UserGeneratedContent.has_recently_updated_content?(:issue_comments, @user.id, since: 3.minutes)
        end
      end
    end

    test "does not blow up for any registered tables" do
      Spam::Spammable.tables_classes_including.each_key do |table|
        assert_nothing_raised do
          Spam::UserGeneratedContent.has_recently_updated_content?(table, @user.id)
        end
      end
    end
  end
end
