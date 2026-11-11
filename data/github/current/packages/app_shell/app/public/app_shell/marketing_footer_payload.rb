# typed: strict
# frozen_string_literal: true

module AppShell
  # Props for the @github-ui/marketing-footer React partial. Keys are emitted in camelCase to
  # match the partial's TypeScript prop contract (packages/marketing-footer/
  # marketing-footer.types.ts in github/github-ui), consistent with the other AppShell payload
  # classes (FooterPayload, AppShellLayoutPayload, etc.).
  class MarketingFooterPayload < ReactPayload::Base
    include UrlHelpers

    ColorMode = T.type_alias { T.any(String, Symbol) }

    sig { override.returns(String) }
    def route_id
      "marketingFooterRoute"
    end

    sig do
      params(
        current_user: T.nilable(User),
        cookie_consent_enabled: T::Boolean,
        color_mode: ColorMode,
        current_locale: T.nilable(String),
        can_toggle_site_admin_and_employee_status: T::Boolean,
        is_admin_mode_on: T::Boolean,
        show_ui_opt_out: T::Boolean,
        is_ui_opted_out: T::Boolean
      ).void
    end
    def initialize(
      current_user:,
      cookie_consent_enabled: false,
      color_mode: "auto",
      current_locale: nil,
      can_toggle_site_admin_and_employee_status: false,
      is_admin_mode_on: false,
      show_ui_opt_out: false,
      is_ui_opted_out: false
    )
      @current_user = current_user
      @cookie_consent_enabled = cookie_consent_enabled
      @color_mode = color_mode
      @current_locale = current_locale
      @can_toggle_site_admin_and_employee_status = can_toggle_site_admin_and_employee_status
      @is_admin_mode_on = is_admin_mode_on
      @show_ui_opt_out = show_ui_opt_out
      @is_ui_opted_out = is_ui_opted_out
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        cookieConsentEnabled: @cookie_consent_enabled,
        colorMode: @color_mode.to_s,
        currentLocale: @current_locale,
        localeOptions: locale_options,
        showAdminToggle: @can_toggle_site_admin_and_employee_status,
        isAdminModeOn: @is_admin_mode_on,
        adminTogglePath: @can_toggle_site_admin_and_employee_status ? site_admin_and_employee_status_path : nil,
        showUiOptOut: @show_ui_opt_out,
        isUiOptedOut: @is_ui_opted_out,
        uiOptOutTogglePath: @show_ui_opt_out ? ui_runtime_opt_out_path : nil,
      }
    end

    private

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def locale_options
      MarketingLocales.enabled_selector_links(@current_user).map do |entry|
        {
          displayName: entry[:display_name],
          selectorLocale: entry[:selector_locale],
          analyticsLabel: entry[:analytics_label],
        }
      end
    end
  end
end
