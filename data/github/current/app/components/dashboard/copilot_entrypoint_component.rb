# typed: strict
# frozen_string_literal: true

module Dashboard
  class CopilotEntrypointComponent < ApplicationComponent
    sig { params(show_header: T::Boolean, unauthorized_sso_orgs: T::Array[T::Hash[String, String]]).void }
    def initialize(show_header: false, unauthorized_sso_orgs: [])
      @show_header = show_header
      @unauthorized_sso_orgs = unauthorized_sso_orgs
    end

    sig { returns(T::Boolean) }
    attr_reader :show_header

    sig { returns(T::Array[T::Hash[String, String]]) }
    attr_reader :unauthorized_sso_orgs

    sig { returns(T.nilable(T::Boolean)) }
    def render?
      return false unless copilot_entrypoint_enabled?

      helpers.show_copilot_chat_entrypoint? && current_copilot_user_v2&.dashboard_entry_point_enabled?
    end

    private

    sig { returns(T::Boolean) }
    def copilot_entrypoint_enabled?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_dashboard_entrypoint)
    end

    sig { returns(T::Array[T.untyped]) }
    def icebreakers
      helpers.get_nux_icebreakers.presence || helpers.get_icebreakers(3)
    end

    sig { returns(T.nilable(Copilot::LimitedUser)) }
    def limited_user
      Copilot::LimitedUser.for_subscribed_user(current_user)
    end

    sig { returns(T.nilable(String)) }
    def reset_date
      limited_user&.reset_date&.strftime("%B %d, %Y")
    end

    sig { returns(String) }
    def display_name
      current_user.display_login
    end

    sig { returns(T::Boolean) }
    def dashboard_modules_enabled?
      T.cast(helpers.dashboard_universe_enabled?, T::Boolean) &&
        !FeatureFlag.vexi.enabled?(:disable_dashboard_lists, current_user, default: false)
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def input_props
      {
        searchWorkerFilePath: find_file_worker_path,
        ssoOrganizations: unauthorized_sso_orgs,
        showHeader: show_header,
        sparkEnabled: current_user.spark_enabled?(check_hierarchy: false),
        userIsOnboarding: current_user.in_onboarding_period?,
        displayName: display_name,
        agentsEnabled: !!current_copilot_user_v2&.swe_agent_enabled?,
        dashboardModulesEnabled: dashboard_modules_enabled?,
        **helpers.copilot_chat_payload(false, [], request)
      }
    end
  end
end
