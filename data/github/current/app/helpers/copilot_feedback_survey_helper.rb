# typed: true
# frozen_string_literal: true

module CopilotFeedbackSurveyHelper
  REPOSITORY_PAGE_SURVEY_TYPES = %w[
    copilot-feedback-survey
    copilot-plg-survey
    copilot-create-issue-feedback
  ].freeze

  # Returns the React props hash for the Copilot self-serve survey banner if
  # `user` is targeted for any of the repository-page surveys, or nil
  # otherwise. Used by both the code view payload and the legacy ERB header
  # partial so the contract stays in sync.
  def copilot_survey_banner_info(user)
    return nil unless user

    survey_type = REPOSITORY_PAGE_SURVEY_TYPES.find do |type|
      Copilot::FeedbackSurvey.show_survey_for_user_repository_page?(user, type)
    end
    return nil unless survey_type

    banner = Copilot::FeedbackSurvey.self_serve_banner(survey_type)

    {
      bannerText: banner&.body,
      bannerTitle: banner&.title,
      ctaUrl: banner&.cta_url,
      ctaText: banner&.cta_text,
      bannerSlug: banner&.slug,
      surveyOpenCallbackPath: Rails.application.routes.url_helpers.copilot_feedback_survey_open_path,
      surveyDismissCallbackPath: Rails.application.routes.url_helpers.copilot_feedback_survey_dismiss_path,
    }
  end
end
