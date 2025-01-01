# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotFeedbackSurveyTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @frozen_date = Time.new(2024, 11, 20, 0, 10, 0).utc
    @org = create(:copilot_for_business_enabled_organization)
    @org.add_member(@user, action: :admin)
    @business = @org.business
    @copilot_survey_slug = "copilot-feedback-survey"

    Copilot::Organization.new(@org).seat_management_allow_all!
    Copilot::Business.new(@business).enable_copilot!
  end

  context "show_survey_for_user_repository_page?", skip_enterprise: true do
    test "do not show survey if there is no logged in user" do
      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(nil, @copilot_survey_slug)

      refute show_survey_prompt
    end

    test "do not show survey if user has dismissed it recently" do
      CopilotPLG::KV.set(Copilot::FeedbackSurvey.key_for_user(@user, @copilot_survey_slug), true.to_json)
      Copilot::FeedbackSurvey.dismiss_survey(@user, @copilot_survey_slug)


      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user, @copilot_survey_slug)

      refute show_survey_prompt
    end

    test "do not show survey if user has opened the survey link" do
      CopilotPLG::KV.set(Copilot::FeedbackSurvey.key_for_user(@user, @copilot_survey_slug), true.to_json)
      Copilot::FeedbackSurvey.opened_survey(@user, @copilot_survey_slug)


      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user, @copilot_survey_slug)

      refute show_survey_prompt
    end

    test "do not show survey if user does not exist in KV" do
      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user, @copilot_survey_slug)

      refute show_survey_prompt
    end

    test "shows banner when user is a targeted user" do
      create :self_serve_banner, slug: @copilot_survey_slug
      CopilotPLG::KV.set(Copilot::FeedbackSurvey.key_for_user(@user, @copilot_survey_slug), true.to_json)


      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user, @copilot_survey_slug)
      assert show_survey_prompt
    end

    test "does not show survey when copilot self-serve banner is not visible" do
      create :self_serve_banner, slug: @copilot_survey_slug, visibility: false
      CopilotPLG::KV.set(Copilot::FeedbackSurvey.key_for_user(@user, @copilot_survey_slug), true.to_json)

      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user, @copilot_survey_slug)
      refute show_survey_prompt
    end
  end
end
