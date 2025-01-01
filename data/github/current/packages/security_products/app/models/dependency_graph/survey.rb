# typed: true
# frozen_string_literal: true

class DependencyGraph::Survey
  SLUG = "dependency-graph-feedback"
  HIDE_FOR_DAYS = 90

  def self.hide_for(user)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set(self.hide_key_for(user), "true", expires: HIDE_FOR_DAYS.days.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  def self.hidden_by?(user)
    GitHub.kv.exists(self.hide_key_for(user)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.hide_key_for(user)
    "dependency-graph-feedback-hide-#{user.id}"
  end

  def self.taken_by?(user)
    survey = Survey.find_by(slug: SLUG)

    if survey.present?
      survey.taken_by?(user)
    else
      # If we can't find the Survey we'll return true instead of false.
      # This will prevent the prompt from rendering.
      true
    end
  end
end
