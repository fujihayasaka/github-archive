# typed: true
# frozen_string_literal: true

module Repositories
  module New
    class OwnerMenuOptionComponent < ApplicationComponent
      # Needed for #show_default_branch_settings_link_for? only
      include RepositoriesHelper
      include Repos::GitHubEnterpriseHelper
      include FeatureFlagHelper

      attr_reader :owner_option, :marketplace_listings, :hidden, :org_adminable_by_current_user

      # owner_option                  - (required) User or Organization, used to populate select menu option
      # default_selected_option       - (required) User or Organization, used to determine whether this option is selected
      # access                        - (optional) Symbol, one of :read, :write, :admin. Defaults to nil.
      # allow_internal_repos          - (optional) Boolean, defaults to false.
      # allow_private_repos           - (optional) Boolean, defaults to true.
      # allow_public_repos            - (optional) Boolean, defaults to true.
      # marketplace_listings          - (optional) Hash of installable marketplace apps (see User#installable_marketplace_listings_hash)
      # org_adminable_by_current_user - (optional) Boolean, defaults to nil. If true, the user is an admin on the organization.
      #
      def initialize(
        owner_option:,
        default_selected_option:,
        access: nil,
        allow_internal_repos: false,
        allow_private_repos: true,
        allow_public_repos: true,
        custom_disabled_message: nil,
        hidden: false,
        marketplace_listings: {},
        org_adminable_by_current_user: nil
      )
        @owner_option = owner_option
        @default_selected_option = default_selected_option
        @access = access
        @allow_internal_repos = allow_internal_repos
        @allow_private_repos = allow_private_repos
        @allow_public_repos = allow_public_repos
        @custom_disabled_message = custom_disabled_message
        @hidden = hidden
        @marketplace_listings = marketplace_listings || []
        @org_adminable_by_current_user = org_adminable_by_current_user
      end

      memoize def checked?
        owner_option == default_selected_option
      end

      memoize def disabled?
        (is_organization? && access == :read) ||
        custom_disabled_message.present? ||
        disable_personal_account_in_options? ||
        (is_organization? && owner_option.archived?)
      end

      def custom_disabled_message
        @custom_disabled_message
      end

      memoize def disable_personal_account_in_options?
        (is_enterprise_managed? || is_enterprise_to_restrict_for_personal_namespace?) && is_personal_namespace? && restrict_create_repository_in_personal_namespace_setting_enabled?
      end

      memoize def is_enterprise_managed?
        current_user.is_enterprise_managed? if !is_organization?
      end

      memoize def restrict_create_repository_in_personal_namespace_setting_enabled?
        restrict_create_repositories_in_personal_namespace?(current_user)
      end

      memoize def is_personal_namespace?
        !is_organization? && owner_option == current_user
      end

      def is_enterprise_to_restrict_for_personal_namespace?
        GitHub.single_business_environment?
      end

      memoize def has_trade_restrictions?
        owner_option.has_any_trade_restrictions?
      end

      memoize def is_organization?
        owner_option.organization?
      end

      memoize def org_adminable_by_current_user?
        is_organization? && (!!org_adminable_by_current_user || owner_option.adminable_by?(current_user))
      end

      memoize def org_can_add_private_repo?
        is_organization? && owner_option.can_add_private_repo?
      end

      memoize def org_show_upgrade?
        is_organization? && \
            owner_option.at_private_repo_limit? && \
            org_adminable_by_current_user?
      end

      memoize def show_default_branch_settings_link?
        if GitHub.create_repo_perf?
          show_default_branch_settings_link_for?(owner_option, org_adminable_by_current_user:)
        else
          show_default_branch_settings_link_for?(owner_option)
        end
      end

      def org_allow_internal_repos?
        return false unless is_organization?
        allow_internal_repos
      end

      def org_allow_private_repos?
        return true unless is_organization?
        allow_private_repos && \
          org_can_add_private_repo? && \
          owner_option.restriction_tier_allows_feature?(type: :repository)
      end

      def org_allow_public_repos?
        return true unless is_organization?
        allow_public_repos
      end

      def show_quick_install?
        !disabled? && !hidden
      end

      memoize def render_marketplace_listings?
        if GitHub.create_repo_perf? && marketplace_listings.empty?
          return false
        end

        true
      end

      def permission
        disabled? ? "no" : "yes"
      end

      def owner_settings_link_prefix
        if is_organization?
          "#{owner_option.safe_profile_name}'s"
        else
          "your"
        end
      end

      def owner_settings_url
        if is_organization?
          settings_org_repo_defaults_path(owner_option)
        else
          settings_repositories_path
        end
      end

      private

      attr_reader :default_selected_option, :access, :allow_internal_repos, :allow_private_repos, :allow_public_repos
    end
  end
end
