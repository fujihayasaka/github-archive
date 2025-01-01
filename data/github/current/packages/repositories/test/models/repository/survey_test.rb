# typed: true
# frozen_string_literal: true

require "test_helper"

class Repository::SurveyTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  setup do
    disable_feature_flag(:repositories_survey_forced, @user)
  end

  test "hides survey based on FF regardless of user survey status" do
    disable_feature_flag(:repositories_survey, @user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(true)

    refute Repository::Survey.show_survey_prompt_for_user?(@user)
  end

  test "hides survey if user is not in current survey, completed or dismissed it" do
    enable_feature_flag(:repositories_survey, @user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(false)

    refute Repository::Survey.show_survey_prompt_for_user?(@user)
  end

  test "shows survey based on force FF regardless of user survey status" do
    enable_feature_flag(:repositories_survey_forced, @user)
    disable_feature_flag(:repositories_survey, @user)
    Surveys::SurveyHelper.any_instance.stubs(:show_survey_prompt_for_user?).returns(false)

    assert Repository::Survey.show_survey_prompt_for_user?(@user)
  end
end
