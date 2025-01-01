# typed: true
# frozen_string_literal: true

module CopilotSweAgent
  module Helpers

    sig { params(repository: (::Repository), author: T.nilable(::User), viewer: T.nilable(::User)).returns(T::Boolean) }
    def self.is_swe_agent_feedback_visible?(repository, author, viewer)
      return false if viewer.nil? || author.nil? || repository.nil?
      !!(viewer.feature_enabled?(:copilot_swe_agent_feedback) &&
      repository.copilot_swe_agent_enabled?(viewer) &&
      is_user_swe_agent?(author))
    end

    sig { params(pull: PullRequest).returns(T::Boolean) }
    def self.authored_by_agent?(pull)
      !!pull.user && is_user_swe_agent?(pull.user)
    end

    sig { returns(String) }
    def self.feedback_caption_body_text
      "Copilot is powered by AI, so mistakes are possible. Review before merging. Improve Copilot by leaving feedback using the 👍 or 👎 buttons."
    end

    sig { returns(String) }
    def self.feedback_caption_comment_text
      "Help improve Copilot by leaving feedback using the 👍 or 👎 buttons"
    end

    sig { params(maybe_bot_user: T.nilable(::User)).returns(T::Boolean) }
    def self.is_user_swe_agent?(maybe_bot_user)
      if maybe_bot_user.is_a?(::Bot)
        bot_user = T.cast(maybe_bot_user, ::Bot)
        integration = bot_user.integration
        if integration.nil?
          return false
        else
          return integration.id == Apps::Privileged.integration(:copilot_swe_agent).id
        end
      end

      false
    end

    sig do
      params(
        request_id: T.nilable(String),
        organization_id: T.nilable(Integer),
        repository_id: Integer,
        pull_request_id: Integer,
        analytics_tracking_id: T.nilable(String),
        feedback: String,
        feedback_target: String,
        feedback_target_id: String,
        feedback_choice: T.nilable(T::Array[String]),
        text_response: T.nilable(String),
      ).void
    end
    def self.instrument_swe_agent_feedback(
      request_id:,
      organization_id:,
      repository_id:,
      pull_request_id:,
      analytics_tracking_id:,
      feedback:,
      feedback_target:,
      feedback_target_id:,
      feedback_choice:,
      text_response:
    )
      context = {
        organization_id:,
        repository_id:,
        pull_request_id:,
        feedback_target:,
        feedback_target_id:,
        analytics_tracking_id:,
        request_id:,
      }

      payload = { type: feedback }
      GlobalInstrumenter.instrument("copilot.v0.SweAgentFeedback", payload.merge(context))

      if text_response.present?
        restricted_payload = { text_response:, feedback_choice: }
        GlobalInstrumenter.instrument("copilot.v0.SweAgentRestrictedFeedback", restricted_payload.merge(context))
      end
    end
  end
end
