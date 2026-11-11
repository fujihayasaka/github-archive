# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module Helpers
    @current_user_can_push = T.let(false, T::Boolean)
    sig { params(pull: PullRequest, viewer: ::User).returns(T::Hash[Symbol, T.untyped]) }
    def self.status_widget_react_payload(pull, viewer)
      pull_data = {
        id: pull.id,
        global_relay_id: pull.global_relay_id,
        number: pull.number,
        state: pull.state,
        title: pull.title,
        reviewable_state: pull.reviewable_state
      }
      repo_data = Repos::ReactPayload.current_repository_payload(
        pull.repository,
        current_user_can_push: @current_user_can_push
      )
      {
        sessionsPollingInterval: (CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0),
        pull: pull_data,
        repository: repo_data,
      }
    end

    sig { params(sessions: T::Array[CopilotSessions::AgentSession], pull: PullRequest).returns(T::Array[CopilotSessions::Payloads::AgentMention::AgentMentionHash]) }
    def self.get_agent_mentions_for_sessions(sessions, pull)
      comment_ids = []
      review_ids = []

      sessions.each do |session|
        event_identifiers = session.session["event_identifiers"]
        next if event_identifiers.nil?

        case session.event_type
        when "pull_request_comment", "pull_request_comment_non_copilot_pull_request"
          comment_ids.concat(event_identifiers.compact.filter_map { |id| id.to_i if id.to_s.match?(/\A\d+\z/) }) # Ensure only integers are included
        when "pull_request_review", "pull_request_review_non_copilot_pull_request"
          review_ids.concat(event_identifiers.compact.filter_map { |id| id.to_i if id.to_s.match?(/\A\d+\z/) })
        end
      end

      loader = CopilotSessions::AgentMentionsLoader.new(
        pull_request: pull,
        comment_ids: comment_ids,
        review_ids: review_ids
      )

      loader.load_all
    end
  end
end
