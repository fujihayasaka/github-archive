# typed: false
# frozen_string_literal: true

require "test_helper"

class SurveyHelperTest < GitHub::TestCase
  fixtures do
    # This id must currently be hardcoded to something that will fall into
    # the survey set during tests
    @user = User.find_by_id(1) || create(:user, id: 1)
    @frozen_date = Time.new(2020, 4, 1, 0, 10, 0).utc.freeze
  end

  setup do
    @survey = Surveys::SurveyHelper.new(slug: "test_survey", cooldown_days: 90, user_rate_percent: 30)
  end

  if GitHub.enterprise?
    test "do not show survey for enterprise" do
      refute @survey.show_survey_prompt_for_user? @user
    end
  else
    test "do show survey if user has not answered or dismissed and is in current set" do
      Timecop.freeze(@frozen_date) do
        assert  @survey.show_survey_prompt_for_user? @user
      end
    end

    test "do not show survey if user has dismissed it recently" do
      @survey.stub(:user_in_current_survey?, true) do
        Timecop.freeze(@frozen_date) do
          @survey.dismiss_survey(@user)

          refute @survey.show_survey_prompt_for_user? @user
        end
      end
    end

    test "do show survey if user has dismissed it more than 90 days ago and is in the current set" do
      Timecop.freeze(@frozen_date) do
        Timecop.travel(91.days.ago) do
          @survey.dismiss_survey(@user)
        end

        show_survey_prompt = @survey.show_survey_prompt_for_user? @user

        assert show_survey_prompt
      end
    end

    test "do not show survey if user has answered it recently" do
      Timecop.freeze(@frozen_date) do
        @survey.answered_survey(@user)
        show_survey_prompt = @survey.show_survey_prompt_for_user? @user

        refute show_survey_prompt
      end
    end

    test "do show survey if user has answered it more than 90 days ago" do
      Timecop.freeze(@frozen_date) do
        Timecop.travel(91.days.ago) do
          @survey.answered_survey(@user)
        end

        show_survey_prompt = @survey.show_survey_prompt_for_user? @user

        assert show_survey_prompt
      end
    end

    test "only show survey if user is in current set of users" do
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = @survey.show_survey_prompt_for_user? @user

        assert show_survey_prompt
      end

      Timecop.freeze(Time.new(2020, 5, 1, 0, 10, 0).utc) do
        refute @survey.show_survey_prompt_for_user? @user
      end
    end

    test "show survey for ~30% of users each month" do
      user_count = 1000

      (1..12).each do |month|
        Timecop.freeze(Time.new(2020, month, 22, 14, 52, 15).utc) do
          enabled_for_users = (1..user_count).count do |i|
            @survey.user_in_current_survey?(User.new(id: i))
          end

          assert_in_delta(30.0, enabled_for_users / user_count.to_f * 100.0, 5.0)
        end
      end
    end
  end
end
