# typed: strict
# frozen_string_literal: true

module AppShell
  class AppShellLayoutPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "appShellLayoutRoute"
    end

    sig do
      params(
        message: String,
        current_user: User,
        staff_bar_enabled: T::Boolean,
        canary_cookie_enabled: T::Boolean,
        can_toggle_site_admin_and_employee_status: T::Boolean,
        is_admin_mode_on: T::Boolean,
        show_ui_opt_out: T::Boolean,
        is_ui_opted_out: T::Boolean,
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        selected_link: T.nilable(String),
        flash: T.nilable(T::Array[[String, String]]),
        sso_orgs: T.nilable(T::Array[T::Hash[Symbol, String]]),
        no_horizontal_padding: T::Boolean
      ).void
    end
    def initialize(message, current_user:, staff_bar_enabled:, canary_cookie_enabled:, can_toggle_site_admin_and_employee_status: false, is_admin_mode_on: false, show_ui_opt_out: false, is_ui_opted_out: false, current_repository: nil, current_organization: nil, selected_link: nil, flash: nil, sso_orgs: nil, no_horizontal_padding: false)
      @message = message
      @current_user = current_user
      @current_repository = current_repository
      @current_organization = current_organization
      @selected_link = selected_link
      @canary_cookie_enabled = canary_cookie_enabled
      @staff_bar_enabled = staff_bar_enabled
      @can_toggle_site_admin_and_employee_status = can_toggle_site_admin_and_employee_status
      @is_admin_mode_on = is_admin_mode_on
      @show_ui_opt_out = show_ui_opt_out
      @is_ui_opted_out = is_ui_opted_out
      @no_horizontal_padding = no_horizontal_padding
      @flash = flash
      @sso_orgs = sso_orgs
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      global_nav_payload = GlobalNavigation::GlobalNavigationPayload.new(
        current_user: @current_user,
        current_copilot_user: current_copilot_user,
        current_repository: @current_repository,
        current_organization: @current_organization,
        selected_link: @selected_link,
        is_search_page: false, # TODO: get is_search_page
        view: view,
        source: "app_shell"
      )

      staffbar_payload = AppShell::StaffbarPayload.new(canary_cookie_enabled: @canary_cookie_enabled) if @staff_bar_enabled

      footer_payload = AppShell::FooterPayload.new(
        can_toggle_site_admin_and_employee_status: @can_toggle_site_admin_and_employee_status,
        is_admin_mode_on: @is_admin_mode_on,
        no_horizontal_padding: @no_horizontal_padding,
        show_ui_opt_out: @show_ui_opt_out,
        is_ui_opted_out: @is_ui_opted_out
      )

      global_banners_payload = AppShell::GlobalBannersPayload.new(flash: @flash, sso_orgs: @sso_orgs)

      {
        someField: @message,
        globalNavigation: global_nav_payload.payload(
          return_to: nil, # TODO: get return_to_path
          display_switch_account_popover: false, # TODO: get display_switch_account_popover?
          context_crumb: nil, # TODO: get context_crumb
          path_resolver: nil, # TODO: get path_resolver
          params: nil # TODO: get params
        ),
        staffbar: staffbar_payload&.payload,
        footer: footer_payload.payload,
        globalBanners: global_banners_payload.payload
      }
    end

    sig { returns(Site::HeaderView) }
    def view
      Site::HeaderView.new(
        current_user: @current_user,
        current_repository: @current_repository,
        current_organization: @current_organization,
        is_mobile_request: false, # TODO: GitHub::Mobile.mobile_user_agent?(request.user_agent.to_s)
        current_copilot_user: current_copilot_user, # TODO: get current_copilot_user from controller context
        params: nil, # TODO: get params from controller context
        response: nil # TODO: get response from controller context,
      )
    end

    sig { returns(Copilot::Public::User) }
    def current_copilot_user
      @current_copilot_user ||= T.let(Copilot::Public::User.for(@current_user), T.nilable(Copilot::Public::User))
    end
  end
end
