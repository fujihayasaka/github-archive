# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class SelfServeBanner
    sig { params(user: User, self_serve_banner_slug: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.banner_properties(user, self_serve_banner_slug)
      return nil unless Copilot::FeedbackSurvey.show_survey_for_user(user, self_serve_banner_slug)

      banner = Copilot::FeedbackSurvey.self_serve_banner(self_serve_banner_slug)
      return nil unless banner

      {
        bannerText: banner.body,
        bannerTitle: banner.title,
        ctaUrl: banner.cta_url,
        ctaText: banner.cta_text,
        bannerSlug: banner.slug,
        surveyOpenCallbackPath: Rails.application.routes.url_helpers.copilot_feedback_survey_open_path,
        surveyDismissCallbackPath: Rails.application.routes.url_helpers.copilot_feedback_survey_dismiss_path,
        icon: "shield",
      }
    end
  end
end
