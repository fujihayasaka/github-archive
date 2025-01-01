# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UserDrawerSidePanelComponent < SidePanelComponent
      include UsersHelper
      include GistsHelper
      include ReactHelper

      attr_reader :user_can_create_organizations, :repository, :memex_enabled, :account_switcher_helper, :eager_load_global_nav

      def initialize(load_everything: false, user_can_create_organizations: false, repository: nil, memex_enabled: false, account_switcher_helper: nil, user: nil, has_unseen_features: false, eager_load_global_nav: false, **system_arguments)
        super(load_everything: load_everything, rich_content_enabled: true) # rich content for the user drawer does not need to be feature flagged

        @user_can_create_organizations = user_can_create_organizations
        @repository = repository
        @memex_enabled = memex_enabled
        @account_switcher_helper = account_switcher_helper
        @user = user
        @has_unseen_features = has_unseen_features
        @eager_load_global_nav = eager_load_global_nav
        @system_arguments = system_arguments
      end

      def create_menu_props
        Site::Header::AddDropdownComponentProps.new(
          current_user: current_user,
          current_organization: current_organization,
          user_can_create_organizations: user_can_create_organizations,
          repository: repository,
          memex_enabled: memex_enabled,
          show_issue_create_link: user_feature_enabled?(:issues_react_global_add),
        ).create_menu_props
      end

      def trigger_data
        data = super
        data.merge login: display_login
      end

      def user
        @user || current_user
      end

      def name
        user.profile_name
      end

      def display_login
        user.display_login
      end

      def projects_path
        user_path(user, params: { tab: "projects" })
      end

      def show_your_gists_url?(user)
        GitHub.gist_enabled?(user)
      end

      def your_gists_url
        my_gists_url
      end

      def show_your_sponsors_url?
        GitHub.sponsors_enabled?
      end

      def your_sponsors_url
        sponsors_accounts_path
      end

      def show_account_switcher?
        return @account_switcher_helper.enabled? if @account_switcher_helper
        false
      end

      def show_feature_preview_url?
        !GitHub.enterprise?
      end

      def show_your_enterprises_link?
        show_your_enterprises_user_menu?
      end

      def show_your_organizations_link?
        return false if user&.is_enterprise_managed? && user&.enterprise_managed_business&.seats_plan_basic?
        true
      end

      def settings_url
        settings_user_profile_path
      end

      def show_enterprise_settings_link?
        show_enterprise_settings_user_menu?
      end

      def enterprise_settings_url
        return unless GitHub.single_business_environment?
        enterprise_url(GitHub.global_business.slug)
      end

      def show_your_enterprise_link?
        show_your_enterprise_user_menu?
      end

      def your_enterprise_url
        return unless show_your_enterprise_user_menu?
        enterprise_url(your_enterprise_user_menu_slug)
      end

      def primary_avatar_url
        user.primary_avatar_url
      end

      def can_add_accounts
        @account_switcher_helper&.can_add_account? || false
      end

      def switch_account_path
        helpers.switch_account_path
      end
    end
  end
end
