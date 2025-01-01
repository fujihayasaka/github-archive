# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @onboarding = Onboarding.for(@user)
  end

  context ".for" do
    test "initializes an onboarding object for a user" do
      assert_kind_of Onboarding, @onboarding
    end
  end

  context "#enrolled_in_welcome_series?" do
    test "true if the user has enrolled in the welcome series" do
      create :onboarding_event, user: @user, name: "enrolled_in_welcome_series"
      assert @onboarding.enrolled_in_welcome_series?
    end

    test "false otherwise" do
      refute @onboarding.enrolled_in_welcome_series?
    end
  end

  context "#welcomed_via_email?" do
    test "true if the user has been welcomed via email" do
      create :onboarding_event, user: @user, name: "welcomed_via_email"
      assert @onboarding.welcomed_via_email?
    end

    test "false otherwise" do
      refute @onboarding.welcomed_via_email?
    end
  end

  context "#enrolled_in_welcome_series!" do
    test "returns error if the event already exists for the user" do
      create :onboarding_event, user: @user, name: "enrolled_in_welcome_series"
      result = @onboarding.enrolled_in_welcome_series!
      refute result.ok?
      assert_equal "already enrolled in welcome series", result.error.message
    end

    test "creates an event" do
      refute @onboarding.enrolled_in_welcome_series?

      assert_difference "Onboarding::Event.count", 1 do
        @onboarding.enrolled_in_welcome_series!
      end

      assert @onboarding.enrolled_in_welcome_series?
    end

    test "records the 'created_at' time automatically" do
      result = @onboarding.enrolled_in_welcome_series!
      assert result.ok?
      event = result.value { nil }
      refute_nil event
      refute_nil event.created_at
    end
  end

  context "#welcomed_via_email!" do
    test "returns error if the event already exists for the user" do
      create :onboarding_event, user: @user, name: "welcomed_via_email"
      result = @onboarding.welcomed_via_email!
      refute result.ok?
      assert_equal "already welcomed via email", result.error.message
    end

    test "creates an event" do
      refute @onboarding.welcomed_via_email?

      assert_difference "Onboarding::Event.count", 1 do
        @onboarding.welcomed_via_email!
      end

      assert @onboarding.welcomed_via_email?
    end
  end

  context "#answered_user_identification_questions!" do
    test "returns error if the event already exists for the user" do
      create :onboarding_event, user: @user, name: "answered_user_identification_questions"
      result = @onboarding.answered_user_identification_questions!
      refute result.ok?
      assert_equal "already answered user identification questions", result.error.message
    end

    test "creates an event" do
      refute @onboarding.answered_user_identification_questions?

      assert_difference "Onboarding::Event.count", 1 do
        @onboarding.answered_user_identification_questions!
      end

      assert @onboarding.answered_user_identification_questions?
    end
  end

  context "#answered_user_identification_questions?" do
    test "true if the user has been welcomed via email" do
      create :onboarding_event, user: @user, name: "answered_user_identification_questions"
      assert @onboarding.answered_user_identification_questions?
    end

    test "false otherwise" do
      refute @onboarding.answered_user_identification_questions?
    end
  end
end
