# typed: true
# frozen_string_literal: true

class Copilot::FeedbackSurvey
  extend GitHub::ResilienceMixin

  sig { params(user: T.nilable(User)).returns(String) }
  def self.survey_url(user)
    "https://github.surveymonkey.com/r/LPCZZCK?uid=[#{user&.display_login}]"
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def self.show_survey_for_user_repository_page?(user)
    return false unless user
    return false unless GitHub.copilot_enabled?
    return false unless user.feature_enabled?(:copilot_inactive_business_users_feedback_survey)
    return false if self.survey_hidden_for_user?(user)

    copilot_user = Copilot::Public::User.new(user)
    copilot_user.has_cb_access?
  end

  sig { params(user: T.nilable(User)).void }
  def self.dismiss_survey(user)
    return unless user

    self.hide_survey_for_user(user)
    self.emit_stat("dismissed")
  end

  sig { params(user: T.nilable(User)).void }
  def self.opened_survey(user)
    return unless user

    self.hide_survey_for_user(user)
    self.emit_stat("opened")
  end

  sig { params(user: User).returns(T::Boolean) }
  def self.survey_hidden_for_user?(user)
    value = ActiveRecord::Base.connected_to(role: :reading) do
      SecurityProductsEnablement::KV.get(self.key_for_user(user)).value { "false" }
    end

    value != "true"
  end

  sig { params(user: T.nilable(User)).void }
  def self.hide_survey_for_user(user)
    return unless user

    ActiveRecord::Base.connected_to(role: :writing) do
      SecurityProductsEnablement::KV.set(self.key_for_user(user), "false", expires: 30.days.from_now)
    end
  end

  sig { params(user: User).returns(String) }
  def self.key_for_user(user)
    "user.copilot-feedback-survey-visible.#{user.id}"
  end

  # Public: emit a counter in the context for the survey including the given action as tag
  def self.emit_stat(action)
    GitHub.dogstats.increment("copilot_inactive_business_users_feedback_survey", tags: ["action:#{action}"])
  end
end
