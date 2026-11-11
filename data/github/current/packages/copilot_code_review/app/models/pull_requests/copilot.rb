# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    extend GitHub::ResilienceMixin

    sig { params(copilot_user: T.nilable(T.any(::Copilot::User, ::Copilot::Public::User))).returns(T::Boolean) }
    def self.copilot_for_prs_enabled?(copilot_user)
      with_database_error_fallback(fallback: false) do
        next false unless copilot_user

        copilot_user.pr_summarizations_enabled?
      end
    end

    sig do
      params(
        request_id: T.nilable(String),
        organization_id: T.nilable(Integer),
        repository_id: Integer,
        pull_request_id: Integer,
        comment_id: String,
        analytics_tracking_id: T.nilable(String),
        feedback: String,
        feedback_choice: T.nilable(T::Array[String]),
        text_response: T.nilable(String),
        custom_instructions_included: T::Boolean,
        copilot_access_type: T.nilable(Symbol),
        comment_identifier: T.nilable(String),
        feedback_target: T.nilable(String),
      ).void
    end
    def self.instrument_code_review_feedback(
      request_id:,
      organization_id:,
      repository_id:,
      pull_request_id:,
      comment_id:,
      analytics_tracking_id:,
      feedback:,
      feedback_choice:,
      text_response:,
      custom_instructions_included:,
      copilot_access_type:,
      comment_identifier: nil,
      feedback_target: nil
    )
      context = {
        request_id:,
        organization_id:,
        repository_id:,
        pull_request_id:,
        comment_id:,
        comment_identifier:,
        analytics_tracking_id:,
        custom_instructions_included:,
        copilot_access_type:,
        feedback_target:,
      }

      payload = { type: feedback }
      GlobalInstrumenter.instrument("copilot.reviews.v0.Feedback", payload.merge(context))

      if feedback_choice.present? || text_response.present?
        restricted_payload = { feedback_choice:, text_response: }
        GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedFeedback", restricted_payload.merge(context))
      end
    end
  end
end
