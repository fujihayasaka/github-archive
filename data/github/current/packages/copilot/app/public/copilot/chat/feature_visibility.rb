# typed: strict
# frozen_string_literal: true

module Copilot
  module Chat
    module FeatureVisibility
      extend T::Helpers
      requires_ancestor { ApplicationController }

      sig { returns(T::Boolean) }
      def can_show_copilot_button_in_job_logs_ui?
        return false unless feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_job_logs_ui)

        with_database_error_fallback(fallback: false) do
          if feature_enabled_globally_or_for_user?(feature_name: :"copilot_chat_explain_error_ga")
            helpers.copilot_chat_enabled_for_current_user?
          else
            !!(helpers.copilot_chat_enabled_for_current_user? && current_copilot_user_v2&.beta_features_github_chat_enabled?)
          end
        end
      end

      sig { returns(T::Boolean) }
      def can_show_copilot_action_in_mergebox_ui?
        can_show_copilot_button_in_job_logs_ui?
      end
    end
  end
end
