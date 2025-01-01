# typed: true
# frozen_string_literal: true

require "react_payload"

class ReactAppShellController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:layout]
  before_action :require_app_shell_feature_flag

  # provides a JSON payload for the app shell layout route
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        payload = AppShell::AppShellLayoutPayload.new("A message from the App Shell layout")
        render_react_json(payload: payload)
      end
    end
  end

  private

  def require_app_shell_feature_flag
    # Treat as not found unless a user is logged in AND the feature flag is enabled
    render_404 unless logged_in? && user_or_global_feature_enabled?(:force_react_app_shell)
  end

  # Conditional Access Policy (CAP) hook: this endpoint has no CAP target
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
