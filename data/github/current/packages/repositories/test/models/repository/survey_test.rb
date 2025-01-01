# typed: true
# frozen_string_literal: true

require "test_helper"

class Repository::SurveyTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  setup do
    GitHub.flipper[:repositories_survey_forced].disable(@user)
  end

  test "hides survey based on FF regardless of user survey status" do
    GitHub.flipper[:repositories_survey].disable(@user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(true)

    refute Repository::Survey.show_survey_prompt_for_user?(@user)
  end

  test "hides survey if user is not in current survey, completed or dismissed it" do
    GitHub.flipper[:repositories_survey].enable(@user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(false)

    refute Repository::Survey.show_survey_prompt_for_user?(@user)
  end

  test "shows survey based on force FF regardless of user survey status" do
    GitHub.flipper[:repositories_survey_forced].enable(@user)
    GitHub.flipper[:repositories_survey].disable(@user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(false)

    assert Repository::Survey.show_survey_prompt_for_user?(@user)
  end
end
