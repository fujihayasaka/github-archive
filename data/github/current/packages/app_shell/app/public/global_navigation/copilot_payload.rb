# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class CopilotPayload < BasePayload
    include ClientEnvHelper

    sig { override.returns(String) }
    def route_id
      "copilotRoute"
    end

    sig { override.params(include_agents_panel: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def payload(include_agents_panel: false)
      GitHub.dogstats.time("global_navigation.copilot", tags: tracking_tags) do
        include_agents_panel ? copilot_payload_with_agents_panel : copilot_payload
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def copilot_payload_with_agents_panel
      copilot_payload.dup.merge(agentsPanel: agents_panel_payload)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def copilot_payload
      GitHub.dogstats.time("global_navigation.copilot.base", tags: tracking_tags) do
        {
          show: show_copilot_buttons?,
          showAgentsButton: show_agents_button?,
          copilotChatUrl: copilot_chat_url,
          copilotApiUrl: copilot_api_override_url_with_fallback(current_user),
        }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def agents_panel_payload
      return {} unless show_agents_button?

      GitHub.dogstats.time("global_navigation.copilot.agents_panel", tags: tracking_tags) do
        {
          agentsButtonId: "global-copilot-agent-button",
          popoverAvailable: show_copilot_coding_agent_entry_point_popover?,
          repository: repo_for_react,
          linkToSessionsInRepo: link_to_sessions_in_repo?,
          freeUserPopoverAvailable: show_free_user_popover?,
          decoupledModeEnabled: decoupled_mode_enabled?,
        }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def copilot_panel_payload
      GitHub.dogstats.time("global_navigation.copilot.copilot_panel", tags: tracking_tags) do
        {
          repository: repo_for_react
        }
      end
    end

    private

    sig { returns(T.nilable(T::Boolean)) }
    def show_copilot_buttons?
      # TODO: verify we don't need to check for request path since we don't show the header in the immersive experience
      GitHub.copilot_enabled? && logged_in? && copilot_enabled? # && request_path(request) != copilot_immersive_path
    end

    sig { returns(T.nilable(T::Boolean)) }
    def show_agents_button?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_global_agent_button) && copilot_coding_agent_enabled?
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def repo_for_react
      return nil if current_repository.nil?

      attrs = {
        id: current_repository&.id,
        name: current_repository&.name,
        owner_login: current_repository&.owner_display_login
      }

      Repos::ReactPayload.camelize_keys(attrs)
    end

    sig { returns(T::Boolean) }
    def copilot_coding_agent_enabled?
      return false unless current_user.present?

      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      with_database_error_fallback(fallback: false) do
        copilot_user.swe_agent_enabled?
      end
    end

    sig { returns(T::Boolean) }
    def show_copilot_coding_agent_entry_point_popover?
      return false unless current_user.present?

      with_database_error_fallback(fallback: false) do
        CopilotSessions::Public.show_copilot_coding_agent_entry_point_popover?(T.must(current_user))
      end
    end

    sig { returns(T.nilable(String)) }
    def copilot_chat_url
      return nil unless show_copilot_buttons?

      # TODO: get scroll_copilot_to_top param
      "#{ copilot_chat_path }?skip_anchor=true" # #{ params[:scroll_copilot_to_top].present? ? "&scroll_copilot_to_top=true" : "" }"
    end

    sig { returns(T::Boolean) }
    def link_to_sessions_in_repo?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_mission_control_link_to_sessions_in_repo) && !feature_enabled_globally_or_for_user?(feature_name: :copilot_mission_control_link_to_hyperspace)
    end

    sig { returns(T::Boolean) }
    def decoupled_mode_enabled?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_mission_control_decoupled_mode)
    end

    sig { returns(T::Boolean) }
    def show_free_user_popover?
      return false unless current_user.present?

      with_database_error_fallback(fallback: false) do
        CopilotSessions::Public.show_free_user_popover?(T.must(current_user))
      end
    end

    # Allows the url helpers to work within providers
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def default_url_options
      { host: GitHub.host_name }
    end
  end
end
