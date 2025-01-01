# typed: strict
# frozen_string_literal: true

module Issues
  module References
    # Component that renders a card for accessing Copilot SWE Agent
    # in the development section of issues and pull requests.
    class CopilotSweAgentComponent < ApplicationComponent
      extend T::Helpers

      sig { returns(PullRequest) }
      attr_reader :pull

      sig { params(pull: PullRequest, active_session: T::Hash[String, T.untyped], current_user_can_push: T::Boolean).void }
      def initialize(pull:, active_session:, current_user_can_push: false)
        @pull = pull
        @current_user_can_push = current_user_can_push
        @active_session = active_session
      end

      sig { returns(T::Boolean) }
      def render?
        !!pull.repository&.copilot_swe_agent_enabled?(current_user) && pull.repository&.copilot_show_swe_agent_card_component?(current_user)
      end

      # Returns an accessible label for the Copilot button
      sig { returns(String) }
      def aria_label
        "Use Copilot to help get this pull request ready to merge"
      end

      # Returns the status text based on session state
      sig { returns(String) }
      def session_status_text
        state = session_state
        case state
        when CopilotSweAgent::SessionState::IN_PROGRESS
          "Copilot is working"
        when CopilotSweAgent::SessionState::COMPLETED
          "Copilot is done"
        when CopilotSweAgent::SessionState::FAILED
          "Copilot has failed"
        when CopilotSweAgent::SessionState::IDLE
          "Copilot is blocked"
        when CopilotSweAgent::SessionState::WAITING_FOR_USER
          "Copilot is waiting for your input"
        when CopilotSweAgent::SessionState::TIMED_OUT
          "Copilot has timed out"
        when CopilotSweAgent::SessionState::CANCELLED
          "Copilot was manually stopped"
        else T.absurd(state)
        end
      end

      # Returns the icon for the Copilot button
      sig { returns(String) }
      def copilot_icon
        state = session_state
        case state
        when CopilotSweAgent::SessionState::IN_PROGRESS, CopilotSweAgent::SessionState::WAITING_FOR_USER, CopilotSweAgent::SessionState::IDLE
          primer_octicon(:copilot, size: :small, "aria-hidden": true)
        when CopilotSweAgent::SessionState::COMPLETED
          primer_octicon(:copilot, size: :small, "aria-hidden": true)
        when CopilotSweAgent::SessionState::FAILED, CopilotSweAgent::SessionState::TIMED_OUT
          primer_octicon(:"copilot-warning", size: :small, classes: "color-fg-danger", "aria-hidden": true)
        when CopilotSweAgent::SessionState::CANCELLED
          primer_octicon(:"square-fill", size: :small, "aria-hidden": true)
        else T.absurd(state)
        end
      end

      sig { returns(String) }
      def time_description
        duration = helpers.precise_duration(last_updated - created, simplified: true, hide_zero_seconds_remainder: true)

        state = session_state
        case state
        when CopilotSweAgent::SessionState::IN_PROGRESS, CopilotSweAgent::SessionState::WAITING_FOR_USER, CopilotSweAgent::SessionState::IDLE
          "started #{duration} ago"
        when CopilotSweAgent::SessionState::COMPLETED
          "completed after #{duration}"
        when CopilotSweAgent::SessionState::FAILED
          "failed after #{duration}"
        when CopilotSweAgent::SessionState::TIMED_OUT
          "timed out after #{duration}"
        when CopilotSweAgent::SessionState::CANCELLED
          "session stopped after #{duration}"
        else T.absurd(state)
        end
      end

      sig { returns(T::Boolean) }
      def relative_time?
        session_state.in?([CopilotSweAgent::SessionState::IN_PROGRESS, CopilotSweAgent::SessionState::WAITING_FOR_USER, CopilotSweAgent::SessionState::IDLE])
      end

      sig { returns(String) }
      def created_at_iso8601
        created.iso8601
      end

      sig { returns(String) }
      def session_path
        repo_agent_session_path(
          session_id: @active_session["id"],
          user_id: pull.repository&.owner_display_login,
          repository: pull.repository,
          pull_number: pull.number,
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def react_payload
        {
          activeSession: @active_session,
          useMockData: GitHub.copilot_swe_agent_mock_session_data,
          sessionsPollingInterval: (CopilotSweAgent::Public.copilot_sessions_polling_interval_seconds.value * 1000.0),
          pull: pull_data,
          repository: repo_data
        }
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def repo_data
        Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: @current_user_can_push
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def pull_data
        {
          id: pull.id,
          number: pull.number,
          state: pull.state,
          title: pull.title,
          reviewable_state: pull.reviewable_state
        }
      end

      sig { returns(CopilotSweAgent::SessionState) }
      def session_state
        CopilotSweAgent::SessionState.deserialize(@active_session["state"])
      end

      sig { returns(Time) }
      memoize def created
        ensure_time(@active_session["created_at"])
      end

      sig { returns(Time) }
      memoize def last_updated
        ensure_time(@active_session["last_updated_at"])
      end

      sig { params(time: T.nilable(T.any(String, Time))).returns(Time) }
      def ensure_time(time)
        case time
        when String
          Time.parse(time)
        when Time
          time
        when nil
          1.second.ago
        else T.absurd(time)
        end
      end
    end
  end
end
