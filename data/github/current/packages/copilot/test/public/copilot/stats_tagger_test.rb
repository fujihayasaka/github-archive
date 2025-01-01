# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotStatsTaggerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  context "#initialize" do
    test "it allows nil copilot_object" do
      tagger = Copilot::StatsTagger.new(copilot_object: nil)
      assert_equal [], tagger.datadog_tags
      expected = {}.with_indifferent_access
      assert_equal expected, tagger.all_tags
      refute tagger.copilot_object
    end

    test "it allows Copilot::User copilot_object" do
      user = Copilot::User.new(create(:user))
      tagger = Copilot::StatsTagger.new(copilot_object: user)
      expected = { user_id: user.user_object.id, user_login: user.user_object.login, is_staff: false }.with_indifferent_access
      assert_equal expected, tagger.all_tags
      assert_equal user, tagger.copilot_object
    end

    test "it allows ::User copilot_object" do
      user = create(:user)
      tagger = Copilot::StatsTagger.new(copilot_object: user)
      expected = { user_id: user.id, user_login: user.login, is_staff: false }.with_indifferent_access

      assert_equal expected, tagger.all_tags
    end

    test "it allows Copilot::FreeUser copilot_object" do
      freeze_time do
        user = create(:user)
        free_user = create(:copilot_free_user, user: user)
        tagger = Copilot::StatsTagger.new(copilot_object: free_user)
        assert_equal [], tagger.datadog_tags
        expected = {
          user_id: user.id,
          user_login: user.login,
          free_user_type: free_user.free_user_type,
          last_checked_date: free_user.last_checked_date.to_s,
          next_check_at: free_user.next_check_at.to_s,
          subscribed: free_user.subscribed.to_s,
          is_staff: false }.with_indifferent_access
        assert_equal expected, tagger.all_tags
        assert_equal user, T.cast(tagger.copilot_object, Copilot::FreeUser).user
      end
    end
  end
end if GitHub.copilot_enabled?
