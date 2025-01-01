# typed: true
# frozen_string_literal: true

module Copilot
  class CodeReviewBeta
    attr_reader :feature_slug, :preview_terms

    DetailLink = Struct.new(:text, :url, keyword_init: true)
    SURVEY_SLUG = "copilot_code_review_public_preview"

    def initialize
      @feature_slug = "copilot_code_review_public_preview"
      @preview_terms = DetailLink.new(
        text: "the pre-release terms",
        url: "https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms"
      )
    end

    sig { returns(String) }
    def feature_name
      "Copilot code review"
    end

    def waitlist
      EarlyAccessMembership.copilot_code_review_waitlist
    end

    def survey
      ActiveRecord::Base.connected_to(role: :writing) do
        Survey.find_or_create_by(slug: SURVEY_SLUG)
      end
    end

    sig { returns(T.class_of(Copilot::CodeReviewBetaOnboardJob)) }
    def onboard_job
      Copilot::CodeReviewBetaOnboardJob
    end

    def only_show_onboardable_members?
      false
    end

    sig { returns(T.class_of(CopilotCodeReviewBetaMailer)) }
    def mailer
      CopilotCodeReviewBetaMailer
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def can_inherit_org_membership?(user)
      return false if user.spammy? || user.has_any_trade_restrictions?

      copilot_user = Copilot::Public::User.new(user)
      return false unless copilot_user.has_copilot_access?

      true
    end

    sig { returns(T::Boolean) }
    def supply_onboarding_actor?
      true
    end
  end
end
