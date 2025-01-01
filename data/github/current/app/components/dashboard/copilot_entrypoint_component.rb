# typed: strict
# frozen_string_literal: true

module Dashboard
  class CopilotEntrypointComponent < ApplicationComponent
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

    sig { returns(T::Hash[String, T.untyped]) }
    def input_props
      {
        searchWorkerFilePath: find_file_worker_path,
        **helpers.copilot_chat_payload(false, [], request)
      }
    end
  end
end
