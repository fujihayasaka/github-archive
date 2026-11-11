# typed: true
# frozen_string_literal: true

require "react_payload"

class ReactAppShellController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:layout]

  before_action :require_logged_in_user
  check_for_sso [:layout]

  # provides a JSON payload for the app shell layout route
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        payload = AppShell::AppShellLayoutPayload.new(
          "A message from the App Shell layout",
          current_user: current_user,
          staff_bar_enabled: staff_bar_enabled?,
          canary_cookie_enabled: canary_cookie_enabled?,
          show_ui_opt_out: ui_service_opt_out_enabled?,
          is_ui_opted_out: ui_opted_out?,
          current_repository: current_repository,
          current_organization: current_organization,
          selected_link: selected_link,
          flash: helpers.global_flash,
          sso_orgs: sso_orgs
        )
        render_react_json(payload: payload)
      end
    end
  end

  private

  def sso_orgs
    global_sso_orgs_payload if show_global_sso_banner?
  end

  def current_organization
    # TODO: get current organization from controller context
    nil
  end

  def selected_link
    # TODO: get selected link from controller context
    nil
  end

  def require_logged_in_user
    # Treat as not found unless a user is logged in
    render_404 unless logged_in?
  end

  # Conditional Access Policy (CAP) hook: this endpoint has no CAP target
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
