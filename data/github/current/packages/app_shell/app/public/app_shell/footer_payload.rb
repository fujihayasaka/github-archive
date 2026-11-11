# typed: strict
# frozen_string_literal: true

module AppShell
  class FooterPayload < ReactPayload::Base
    include GitHub::Memoizer
    include UrlHelpers

    sig { override.returns(String) }
    def route_id
      "footerRoute"
    end

    sig do
      params(
        can_toggle_site_admin_and_employee_status: T::Boolean,
        is_admin_mode_on: T::Boolean,
        no_horizontal_padding: T::Boolean,
        show_ui_opt_out: T::Boolean,
        is_ui_opted_out: T::Boolean
      ).void
    end
    def initialize(can_toggle_site_admin_and_employee_status:, is_admin_mode_on: false, no_horizontal_padding: false, show_ui_opt_out: false, is_ui_opted_out: false)
      @can_toggle_site_admin_and_employee_status = can_toggle_site_admin_and_employee_status
      @is_admin_mode_on = is_admin_mode_on
      @no_horizontal_padding = no_horizontal_padding
      @show_ui_opt_out = show_ui_opt_out
      @is_ui_opted_out = is_ui_opted_out
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        showAdminToggle: @can_toggle_site_admin_and_employee_status,
        isAdminModeOn: @is_admin_mode_on,
        showCookieConsentLinks: show_cookie_consent_links?,
        isEnterprise: is_enterprise?,
        helpUrl: GitHub.help_url,
        supportUrl: GitHub.support_url,
        noHorizontalPadding: @no_horizontal_padding,
        adminTogglePath: @can_toggle_site_admin_and_employee_status ? site_admin_and_employee_status_path : nil,
        showUiOptOut: @show_ui_opt_out,
        isUiOptedOut: @is_ui_opted_out,
        uiOptOutTogglePath: @show_ui_opt_out ? ui_runtime_opt_out_path : nil,
      }
    end

    private

    sig { returns(T::Boolean) }
    def show_cookie_consent_links?
      !is_enterprise?
    end

    sig { returns(T::Boolean) }
    def is_enterprise?
      GitHub.single_or_multi_tenant_enterprise?
    end
  end
end
