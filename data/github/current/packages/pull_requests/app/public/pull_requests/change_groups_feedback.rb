# typed: strict
# frozen_string_literal: true

module PullRequests
  module ChangeGroupsFeedback
    FEEDBACK_OPTIONS = T.let([
      { label: "Groups contain changes that do not belong together", value: "NOT_RELEVANT" },
      { label: "Groups are harmful or unsafe", value: "OFFENSIVE_OR_DISCRIMINATORY" },
      { label: "Groups are poorly formatted", value: "POORLY_FORMATTED" },
      { label: "Groups are not helpful", value: "NOT_HELPFUL" },
      { label: "Groups miss changes that should be included", value: "MISSED_CONTENT" },
      { label: "Other", value: "OTHER" }
    ], T::Array[T::Hash[Symbol, String]])

    sig do
      params(
        request_id: T.nilable(String),
        organization_id: T.nilable(Integer),
        repository_id: Integer,
        pull_request_id: Integer,
        head_sha: String,
        base_sha: String,
        analytics_tracking_id: T.nilable(String),
        feedback_type: String, # enum :POSITIVE, :NEGATIVE, :UNKNOWN
        feedback_choice: T.nilable(T::Array[String]),
        text_response: T.nilable(String)
      ).void
    end
    def self.instrument_copilot_change_groups_feedback(
      request_id:,
      organization_id:,
      repository_id:,
      pull_request_id:,
      head_sha:,
      base_sha:,
      analytics_tracking_id:,
      feedback_type:,
      feedback_choice:,
      text_response:)
      context = {
        request_id:,
        organization_id:,
        repository_id:,
        pull_request_id:,
        head_sha:,
        base_sha:,
        analytics_tracking_id:,
      }
      payload = { type: feedback_type }
      GlobalInstrumenter.instrument("pull_request_change_groups.v0.Feedback", payload.merge(context))

      if feedback_choice.present? || text_response.present?
        choice_value = feedback_choice & FEEDBACK_OPTIONS.pluck(:value) || []
        restricted_payload = { feedback_choice: choice_value, text_response: text_response }
        GlobalInstrumenter.instrument("pull_request_change_groups.v0.RestrictedFeedback", restricted_payload.merge(context))
      end
    end
  end
end
