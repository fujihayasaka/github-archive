# typed: true
# frozen_string_literal: true

class Repository::Survey
  SURVEY_SLUG = "repositories_survey"

  # We set user_rate_percent to 100 to control the sample using the FF `repositories_survey`
  @helper = Surveys::SurveyHelper.new(slug: SURVEY_SLUG, cooldown_days: 60, user_rate_percent: 100)

  def self.show_survey_prompt_for_user?(user)
    # Display survey regardless of user survey status
    GitHub.flipper[:repositories_survey_forced].enabled?(user) ||
    GitHub.flipper[:repositories_survey].enabled?(user) && @helper.show_survey_prompt_for_user?(user)
  end

  def self.answered_survey(user)
    @helper.answered_survey(user)
  end

  def self.dismiss_survey(user)
    @helper.dismiss_survey(user)
  end
end
