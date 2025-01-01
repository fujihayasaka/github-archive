# typed: true
# frozen_string_literal: true

class Actions::Survey
  SURVEY_SLUG = "actions_survey"

  # Percentage of users to include each month
  SURVEY_USER_RATE_PERCENT = 30

  # Days to wait after a user has answered/dismissed the survey before asking them again
  SURVEY_COOLDOWN_DAYS = 90

  # Public: returns a value indicating whether the survey prompt should be shown for the given user
  def self.show_survey_prompt_for_user(user)
    return false unless user
    return false if GitHub.enterprise?

    return false unless self.user_in_current_survey(user)
    return false if self.survey_hidden_for_user(user)

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
    GitHub.dogstats.increment("actions_satisfaction_survey", tags: ["action:#{action}"])
  end

  def self.user_in_current_survey(user)
    # Include up to SURVEY_USER_RATE_PERCENT of all users per month
    current_month = Time.now.utc.to_date.month

    Zlib.crc32(user.id.to_s + "actions-survey" + current_month.to_s) % 100 < SURVEY_USER_RATE_PERCENT
  end

  def self.hide_survey_for_user(user)
    return unless user

    kv(user.id).set(self.key_for_user(user), "true", expires: (Date.today + SURVEY_COOLDOWN_DAYS).to_time)
  end

  def self.survey_hidden_for_user(user)
    kv(user.id).exists(self.key_for_user(user)).value { false }
  end

  def self.key_for_user(user)
    "user.actions-survey-hidden.#{user.id}"
  end

  class << self
    private

    def kv(user_id)
      Actions::KV.for_partition_key(user_id)
    end
  end
end
