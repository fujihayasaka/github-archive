# typed: true
# frozen_string_literal: true

class PullRequest::Survey
  SLUG = "pull-request-satisfaction"
  HIDE_FOR_DAYS = 90
  USER_RATE_PERCENT = 30

  def self.hide_for(user)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set(self.hide_key_for(user), "true", expires: HIDE_FOR_DAYS.days.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  def self.hidden_by?(user)
    GitHub.kv.exists(self.hide_key_for(user)).value { true } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.hide_key_for(user)
    "user.pull-requests-survey-hidden.#{user.id}"
  end

  def self.in_current_survey?(user)
    # Include up to USER_RATE_PERCENT of all users per month
    current_month = Time.now.utc.to_date.month

    Zlib.crc32(user.id.to_s + "pull-requests-survey" + current_month.to_s) % 100 < USER_RATE_PERCENT
  end

  def self.new_user?(user)
    user.created_at >= 1.day.ago
  end
end
