# typed: true
# frozen_string_literal: true

class PushProtectionSurvey
  extend T::Sig

  SLUG = "secret-scanning-push-protection-survey"
  HIDE_FOR_DAYS = 90

  sig { params(user: User).returns(T::Boolean) }
  def self.taken_by?(user)
    survey = T.unsafe(Survey).find_by_slug(SLUG)

    if survey.present?
      survey.taken_by?(user)
    else
      # If we can't find the Survey we'll return true instead of false.
      # This will prevent the prompt from rendering.
      true
    end
  end

  # Public: Hide this survey from the user for HIDE_FOR_DAYS days (90 days, at time of writing).
  #
  sig { params(user: User).void }
  def self.hide_for(user)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set(self.hide_key_for(user), "true", expires: HIDE_FOR_DAYS.days.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  sig { params(user: User).returns(T::Boolean) }
  def self.hidden_by?(user)
    GitHub.kv.exists(self.hide_key_for(user)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  sig { params(user: User).returns(String) }
  def self.hide_key_for(user)
    "user.push-protection-survey-hidden.#{user.id}"
  end

  sig { params(user: User).void }
  def self.disabled_push_protection(user)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set(self.disable_key_for(user), "true", expires: HIDE_FOR_DAYS.days.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  sig { params(user: User).returns(T::Boolean) }
  def self.disabled_by?(user)
    GitHub.kv.exists(self.disable_key_for(user)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  sig { params(user: User).returns(String) }
  def self.disable_key_for(user)
    "user.push-protection-disabled.#{user.id}"
  end
end
