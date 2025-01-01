# typed: true
# frozen_string_literal: true

class Copilot::FeedbackSurvey
  extend GitHub::ResilienceMixin

  REPO_PAGE_SURVEY_TYPES = %w(copilot-feedback-survey copilot-plg-survey copilot-create-issue-feedback).freeze

  # The slug here is to match a banner created in stafftools form, browser URL /stafftools/copilot_banners/
  sig { params(slug: String).returns(T.nilable(CopilotPLG::SelfServeBanner)) }
  def self.self_serve_banner(slug)
    begin
      CopilotPLG::SelfServeBanner.find_by(slug: slug)
    rescue ActiveRecord::ActiveRecordError
      nil
    end
  end

  # This checks if the survey should be shown for a user on the repository page for Copilot users.
  sig { params(user: T.nilable(User), slug: String).returns(T::Boolean) }
  def self.show_survey_for_user_repository_page?(user, slug)
    return false unless user
    return false unless GitHub.copilot_enabled?
    return false unless REPO_PAGE_SURVEY_TYPES.include?(slug)

    begin
      # count visible surveys for repo page, return false if somehow both are visible
      visible_count = CopilotPLG::SelfServeBanner
        .where(slug: REPO_PAGE_SURVEY_TYPES)
        .where(visibility: true)
        .count

      # Return false if no surveys visible or multiple visible
      return false if visible_count != 1

      # Now check if this specific survey is visible
      banner = self.self_serve_banner(slug)
      return false unless banner&.visibility?

      kv_state = JSON.parse(fetch_kv_value(user, slug))
      # Only show if banner is visible and not dismissed (kv_state is true)
      kv_state == true
    rescue ActiveRecord::ActiveRecordError, JSON::ParserError
      false
    end
  end

  # This is a general method used to show surveys to any user that was uploaded via CSV.
  sig { params(user: T.nilable(User), slug: String).returns(T::Boolean) }
  def self.show_survey_for_user(user, slug)
    return false unless user

    banner = self.self_serve_banner(slug)
    return false unless banner&.visibility?

    kv_state = JSON.parse(fetch_kv_value(user, slug))
    # Only show if banner is visible and not dismissed (kv_state is true)
    kv_state == true
  end

  sig { params(user: T.nilable(User), slug: String).void }
  def self.dismiss_survey(user, slug)
    return unless user

    self.hide_survey_for_user(user, slug)
    self.emit_stat("dismissed", slug)
  end

  sig { params(user: T.nilable(User), slug: String).void }
  def self.opened_survey(user, slug)
    return unless user

    self.hide_survey_for_user(user, slug)
    self.emit_stat("opened", slug)
  end

  sig { params(user: T.nilable(User), slug: String).void }
  def self.hide_survey_for_user(user, slug)
    return unless user

    ActiveRecord::Base.connected_to(role: :writing) do
      CopilotPLG::KV.set(self.key_for_user(user, slug), false.to_json, expires: 30.days.from_now)
    end
  end

  sig { params(user: User, slug: String).returns(String) }
  def self.key_for_user(user, slug)
    "user.#{slug}-visible.#{user.id}"
  end

  # Public: emit a counter in the context for the survey including the given action as tag
  sig { params(action: String, slug: String).void }
  def self.emit_stat(action, slug)
    GitHub.dogstats.increment("copilot_user_engagement_feedback_survey", tags: ["action:#{action}", "slug:#{slug}"])
  end

  sig { params(user: User, slug: String).returns(String) }
  def self.fetch_kv_value(user, slug)
    key = key_for_user(user, slug)


    ActiveRecord::Base.connected_to(role: :reading) do
      CopilotPLG::KV.get(key).value { false.to_json }
    end || false.to_json
  end

  sig { params(slug: String).returns(Integer) }
  def self.number_of_targeted_users(slug)
    entries = CopilotPLG::KV.mget_prefix("user.#{slug}-visible.")
    entries.value { false.to_json }.count
  end
end
