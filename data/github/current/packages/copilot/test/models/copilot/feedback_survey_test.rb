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

    Copilot::Organization.new(@org).seat_management_allow_all!
    Copilot::Business.new(@business).enable_copilot!
  end

  setup do
    GitHub.flipper[:copilot_inactive_business_users_feedback_survey].enable
  end

  context "show_survey_for_user_repository_page?", skip_enterprise: true do
    test "do not show the survey if the FF is disabled" do
      GitHub.flipper[:copilot_inactive_business_users_feedback_survey].disable
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user)

        refute show_survey_prompt
      end
    end

    test "do not show survey if there is no logged in user" do
      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(nil)

      refute show_survey_prompt
    end

    test "do not show survey if user has dismissed it recently" do
      Copilot::FeedbackSurvey.dismiss_survey(@user)

      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user)

      refute show_survey_prompt
    end

    test "do not show survey if user has opened the survey link" do
      Copilot::FeedbackSurvey.opened_survey(@user)

      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user)

      refute show_survey_prompt
    end

    test "show survey if user exists in KV" do
      SecurityProductsEnablement::KV.set(Copilot::FeedbackSurvey.key_for_user(@user), "true")
      Copilot::Public::User.any_instance.expects(:has_cb_access?).returns(true)
      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user)

      assert show_survey_prompt
    end

    test "do not show survey if user does not exist in KV" do
      show_survey_prompt = Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(@user)

      refute show_survey_prompt
    end
  end
end
