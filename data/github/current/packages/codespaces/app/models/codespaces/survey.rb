# typed: true
# frozen_string_literal: true

class Codespaces::Survey
  # Percentage of users to include each month
  SURVEY_USER_RATE_PERCENT = 30

  # Days to wait after a user has answered/dismissed the survey before asking them again
  SURVEY_COOLDOWN_DAYS = 90

  def self.survey_url(user)
    "https://survey3.medallia.com/?codespaces&id=#{user&.id}"
  end

  def self.show_survey_prompt_for_user_landing_page?(user)
    show = show_survey_prompt_for_user?(user) && user.codespaces.any?
    self.emit_stat("shown") if show
    show
  end

  def self.show_survey_prompt_for_user_repository_page?(user, repository)
    show = !Repository::Survey.show_survey_prompt_for_user?(user) && show_survey_prompt_for_user?(user) && user.codespaces.where(repository:).any?
    self.emit_stat("shown") if show
    show
  end

  # Public: returns a value indicating whether the survey prompt should be shown for the given user
  def self.show_survey_prompt_for_user?(user)
    return false unless user
    return false unless GitHub.codespaces_enabled?
    return true if FeatureFlag.vexi.enabled_or_raise?(:codespaces_survey_forced, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return false unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_survey, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    return false unless self.user_in_current_survey?(user)
    return false if self.survey_hidden_for_user?(user)

    true
  end

  # Public: hide the survey for the given user for SURVEY_COOLDOWN_DAYS and record it as dismissed
  def self.dismiss_survey(user)
    return unless user

    self.hide_survey_for_user(user)
    self.emit_stat("dismissed")
  end

  # Public: hide the survey for the given user for SURVEY_COOLDOWN_DAYS and record it as opened
  def self.opened_survey(user)
    return unless user

    # Mark the survey as hidden so we don't have to query for answers in order to not show
    # the prompt again.
    self.hide_survey_for_user(user)
    self.emit_stat("opened")
  end

  # Public: emit a counter in the context for the survey including the given action as tag
  def self.emit_stat(action)
    GitHub.dogstats.increment("codespaces_satisfaction_survey", tags: ["action:#{action}"])
  end

  def self.user_in_current_survey?(user)
    # Include up to SURVEY_USER_RATE_PERCENT of all users per month
    current_month = Time.now.utc.to_date.month

    Zlib.crc32(user.id.to_s + "codespaces-survey" + current_month.to_s) % 100 < SURVEY_USER_RATE_PERCENT
  end

  def self.hide_survey_for_user(user)
    return unless user

    Codespaces::Kv.store.set(self.key_for_user(user), "true", expires: (Date.today + SURVEY_COOLDOWN_DAYS).to_time)
  end

  def self.survey_hidden_for_user?(user)
    Codespaces::Kv.store.exists(self.key_for_user(user)).value { false }
  rescue StandardError
    # If we can't hit KV for some reason just default to the survey being hidden so we err on the side of not showing
    # it when we could have.
    true
  end

  def self.key_for_user(user)
    "user.codespaces-survey-hidden.#{user.id}"
  end
end
