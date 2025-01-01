# typed: true
# frozen_string_literal: true

require "test_helper"

if Interaction.enabled?
  class UsersInactiveSinceSignupTest < GitHub::TestCase
    fixtures do
      @signup_date = 8.days.ago.freeze

      Timecop.freeze(@signup_date) do
        @user_no_interaction   = create(:user, login: "no-interaction")
        @user_with_interaction = create(:user, login: "with-interaction")
        @user_with_next_day_interaction = create(:user, login: "next-day")
        @user_with_later_interaction = create(:user, login: "with-later")
        @organization = create(:organization, login: "org")

        Interaction.track_pull_request(@user_with_interaction)
      end

      Timecop.freeze(@signup_date.end_of_day + 16.hours) do
        Interaction.track_pull_request(@user_with_next_day_interaction)
      end

      Timecop.freeze(@signup_date.end_of_day + 10.days) do
        Interaction.track_pull_request(@user_with_later_interaction)
      end
    end

    setup do
      @inactive_users = User.inactive_after_signup(@signup_date)
    end

    test "includes those who have not interacted at all" do
      assert @user_no_interaction.interaction.nil?
      assert_includes @inactive_users, @user_no_interaction
    end

    test "includes those who interacted on the signup day" do
      assert @user_with_interaction.interaction, "expected user to have an Interaction record"
      assert_includes @inactive_users, @user_with_interaction
    end

    test "does not include those who interacted after signup" do
      assert @user_with_next_day_interaction.interaction, "expected user to have an Interaction record"
      refute_includes @inactive_users, @user_with_next_day_interaction
      refute_includes @inactive_users, @user_with_later_interaction
    end

    test "does not include organizations" do
      refute_includes @inactive_users, @organization
    end
  end
end
