# typed: true
# frozen_string_literal: true

require "test_helper"

class UserOnboardingTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#programming_experience" do
    test "returns nil when user has not answered the user_indentification survey" do
      assert_nil @user.programming_experience
    end

    test "returns nil when no answer is found for programming experience question" do
      create :onboarding_event, user: @user, name: "answered_user_identification_questions"

      assert_nil @user.programming_experience
    end

    test "returns the text for the user's choice to the programming experience question" do
      create :onboarding_event, user: @user, name: "answered_user_identification_questions"
      question = create(:survey_question, short_text: "level_of_experience")
      choice = create(:survey_choice, {
        question: question,
        text: "Somewhat experienced",
        short_text: "student",
      })
      answer = create(:survey_answer, {
        user: @user,
        choice: choice,
        question: question,
      })

      assert_equal "Somewhat experienced", @user.programming_experience
    end
  end
end
