# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class UserMenuPayload < BasePayload
    include GistsHelper
    include UsersHelper

    sig { returns(T.nilable(AccountSwitcher::Helper)) }
    attr_reader :account_switcher_helper

    sig { override.returns(String) }
    def route_id
      "userMenuRoute"
    end

    sig do
      params(
        current_user: T.nilable(User),
        source: String,
        account_switcher_helper: T.nilable(AccountSwitcher::Helper)
      ).void
    end
    def initialize(
      current_user:,
      source:,
      account_switcher_helper: nil
    )
      super(
        current_user: current_user,
        source: source
      )
      @account_switcher_helper = account_switcher_helper
    end

    sig { override.params(return_to: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def payload(return_to: nil)
      GitHub.dogstats.time("global_navigation.user_menu", tags: tracking_tags) do
        {
          owner: {
            login: current_user&.display_login,
            name: current_user&.display_name,
            avatarUrl: current_user&.primary_avatar_url
          },
          lazyLoadItemDataFetchUrl: side_panels_path(panel: :user, format: :json),
          canAddAccount: account_switcher_helper&.can_add_account? || false,
          addAccountPath: return_to ? add_account_path(return_to: return_to) : login_path(add_account: 1),
          switchAccountPath: switch_account_path,
          loginAccountPath: login_path(add_account: 1),
          projectsPath: user_path(current_user, params: { tab: "projects" }),
          gistsUrl: my_gists_url,
          docsUrl: GitHub.help_url,
          yourEnterpriseUrl:  show_your_enterprise_user_menu? ? enterprise_path(your_enterprise_user_menu_slug) : nil,
          enterpriseSettingsUrl: GitHub.single_business_environment? ? enterprise_path(GitHub.global_business.slug) : nil,
          supportUrl: GitHub.support_url,
          showAccountSwitcher: account_switcher_helper&.enabled? || false,
          showCopilot: !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?,
          showEnterprises: show_your_enterprises_user_menu?,
          showEnterprise: show_your_enterprise_user_menu?,
          showGists: GitHub.gist_enabled?(current_user),
          showOrganizations: current_user&.is_enterprise_managed? && current_user&.enterprise_managed_business&.seats_plan_basic? ? false : true,
          showSponsors: GitHub.sponsors_enabled?,
          showUpgrade: !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?,
          showFeaturesPreviews: !GitHub.enterprise?,
          showEnterpriseSettings: show_enterprise_settings_user_menu?,
        }
      end
    end

    # Allows the url helpers to work within providers
    sig { returns(T::Hash[Symbol, String]) }
    def default_url_options
      { host: GitHub.host_name }
    end
  end
end
