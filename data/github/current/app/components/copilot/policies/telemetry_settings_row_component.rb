# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class TelemetrySettingsRowComponent < ApplicationComponent
      sig do
        params(
          copilot_user: Copilot::User,
          setting_changed: T::Boolean,
        ).void
      end
      def initialize(copilot_user:, setting_changed: false)
        @copilot_user = copilot_user
        @setting_changed = setting_changed
      end

      private

      sig { returns(T::Boolean) }
      def render_github_employee_text?
        @copilot_user.user_object.employee_ignoring_override? && @copilot_user.feature_flag_enabled?(:enable_hubber_telemetry_opt_out, default: false)
      end
    end
  end
end
