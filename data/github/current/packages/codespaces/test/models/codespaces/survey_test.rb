# typed: false
# frozen_string_literal: true

require "test_helper"

class CodespacesSurveyTest < GitHub::TestCase
  UserInSurveyMock = Struct.new(:id)

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    disable_feature_flag(:codespaces_survey_forced)
    enable_feature_flag(:codespaces_survey)
    # This id must currently be hardcoded to something that will fall into
    # the survey set during tests
    @user = User.find_by_id(42) || create(:user, id: 42)
    @frozen_date = Time.new(2020, 4, 1, 0, 10, 0).utc
  end

  context "show_survey_prompt_for_user_landing_page?", skip_enterprise: true do
    test "doesn't show the survey if the user has no codespaces even if they're in the current set" do
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user_landing_page?(@user)

        refute show_survey_prompt
      end
    end

    test "does show the survey if the user has at least one codespace and is in the current set" do
      Timecop.freeze(@frozen_date) do
        create(:codespace, owner: @user)
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user_landing_page?(@user)

        assert show_survey_prompt
      end
    end
  end

  context "show_survey_prompt_for_user_repository_page?", skip_enterprise: true do
    test "doesn't show the survey if the user has no codespaces on the repo even if they're in the current set" do
      disable_feature_flag(:repositories_survey_forced, @user)
      Timecop.freeze(@frozen_date) do
        repository = create(:repository)
        create(:codespace, owner: @user)
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user_repository_page?(@user, repository)

        refute show_survey_prompt
      end
    end

    test "does show the survey if the user has at least one codespace on the repo and is in the current set" do
      disable_feature_flag(:repositories_survey_forced, @user)
      disable_feature_flag(:repositories_survey, @user)
      Timecop.freeze(@frozen_date) do
        codespace = create(:codespace, owner: @user)
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user_repository_page?(@user, codespace.repository)

        assert show_survey_prompt
      end
    end

    test "doesn't show the survey if the user has at least one codespace on the repo and is in the current set but we're also showing a repo survey" do
      enable_feature_flag(:repositories_survey_forced, @user)
      Timecop.freeze(@frozen_date) do
        codespace = create(:codespace, owner: @user)
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user_repository_page?(@user, codespace.repository)

        refute show_survey_prompt
      end
    end
  end

  context "show_survey_prompt_for_user?", skip_enterprise: true do
    test "do not show the survey if the FF is disabled" do
      disable_feature_flag(:codespaces_survey)
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        refute show_survey_prompt
      end
    end

    test "do show survey if user has not answered or dismissed and is in current set" do
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        assert show_survey_prompt
      end
    end

    test "do not show survey if there is no logged in user" do
      show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(nil)

      refute show_survey_prompt
    end

    test "do not show survey if user has dismissed it recently" do
      Codespaces::Survey.stub(:user_in_current_survey?, true) do
        Timecop.freeze(@frozen_date) do
          Codespaces::Survey.dismiss_survey(@user)

          show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

          refute show_survey_prompt
        end
      end
    end

    test "do show survey if user has dismissed it more than 90 days ago and is in the current set" do
      Timecop.freeze(@frozen_date) do
        Timecop.travel((Codespaces::Survey::SURVEY_COOLDOWN_DAYS + 1).days.ago) do
          Codespaces::Survey.dismiss_survey(@user)
        end

        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        assert show_survey_prompt
      end
    end

    test "do not show survey if user has opened it recently" do
      Timecop.freeze(@frozen_date) do
        Codespaces::Survey.opened_survey(@user)

        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        refute show_survey_prompt
      end
    end

    test "do show survey if user has opened it more than 90 days ago" do
      Timecop.freeze(@frozen_date) do
        Timecop.travel((Codespaces::Survey::SURVEY_COOLDOWN_DAYS + 1).days.ago) do
          Codespaces::Survey.opened_survey(@user)
        end

        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        assert show_survey_prompt
      end
    end

    test "only show survey if user is in current set of users" do
      Timecop.freeze(@frozen_date) do
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        assert show_survey_prompt
      end

      Timecop.freeze(Time.new(2020, 5, 1, 0, 10, 0).utc) do
        show_survey_prompt = Codespaces::Survey.show_survey_prompt_for_user?(@user)

        refute show_survey_prompt
      end
    end

    test "show survey for ~30% of users each month" do
      user_count = 1000

      (1..12).each do |month|
        Timecop.freeze(Time.new(2020, month, 22, 14, 52, 15).utc) do
          enabled_for_users = (1..user_count).count do |i|
            Codespaces::Survey.user_in_current_survey?(UserInSurveyMock.new(id: i))
          end

          assert_in_delta(30.0, enabled_for_users / user_count.to_f * 100.0, 5.0)
        end
      end
    end
  end
end
