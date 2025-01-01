# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class LayoutData
      include GitHub::Memoizer
      include AdvancedSecurityEntrypointHelper

      METHODS_TO_PRELOAD = [
        :adminable_by_viewer?,
        :direct_or_team_member?,
        :hide_from_viewer?,
        :login_name,
        :organization_members,
        :primary_avatar_url,
        :profile_name,
        :show_developer_program_member_badge?,
        :show_ghas_trial_upsell_banner?,
        :show_github_sponsor_recognition?,
        :show_sponsor_button?,
        :site_admin_alerts,
        :sponsorable?,
        :sponsored_by_viewer?,
        :user_or_organization_restricted?,
        :viewer,
      ].freeze

      SIDEBAR_MEMBERS_LIMIT = 21
      SPONSORSHIPS_LIMIT = 13

      attr_reader :profile_organization,
        :viewer,
        :active_tab,
        :phrase,
        :sort_order,
        :language,
        :type_filter,
        :view_as,
        :org_profile_readme,
        :item_showcase,
        :any_pinnable_items,
        :viewer_can_change_pinned_items

      def initialize(
        profile_organization:,
        viewer:,
        active_tab:,
        phrase: nil,
        sort_order: nil,
        language: nil,
        type_filter: nil,
        view_as: nil,
        org_profile_readme: nil,
        item_showcase: nil,
        any_pinnable_items: nil,
        viewer_can_change_pinned_items: nil
      )
        @profile_organization = profile_organization
        @viewer = viewer
        @active_tab = active_tab
        @phrase = phrase
        @sort_order = sort_order
        @type_filter = type_filter.present? ? type_filter : default_type_filter
        @language = language
        @view_as = view_as
        @org_profile_readme = org_profile_readme
        @item_showcase = item_showcase
        @any_pinnable_items = any_pinnable_items
        @viewer_can_change_pinned_items = viewer_can_change_pinned_items
      end

      def self.preload(
        profile_organization:,
        viewer:,
        active_tab:,
        phrase: nil,
        sort_order: nil,
        language: nil,
        type_filter: nil,
        view_as: nil,
        org_profile_readme: nil,
        item_showcase: nil,
        any_pinnable_items: nil,
        viewer_can_change_pinned_items: nil
      )
        new(
          profile_organization: profile_organization,
          viewer: viewer,
          active_tab: active_tab,
          phrase: phrase,
          sort_order: sort_order,
          language: language,
          type_filter: type_filter,
          view_as: view_as,
          org_profile_readme: org_profile_readme,
          item_showcase: item_showcase,
          any_pinnable_items: any_pinnable_items,
          viewer_can_change_pinned_items: viewer_can_change_pinned_items,
        ).preload!
      end

      def preload!
        METHODS_TO_PRELOAD.map(&method(:send))

        self
      end

      memoize def adminable_by_viewer?
        profile_organization.adminable_by?(viewer)
      end

      memoize def hide_from_viewer?
        profile_organization.hide_from_user?(viewer)
      end

      memoize def login_name
        profile_organization.display_login
      end

      memoize def direct_or_team_member?
        profile_organization.direct_or_team_member?(viewer)
      end

      def default_type_filter
        return "all" unless
          GitHub.flipper[:default_org_profiles_to_public_repos].enabled?(viewer) ||
          GitHub.flipper[:default_org_profiles_to_public_repos].enabled?(profile_organization)

        if phrase.blank?
          "public"
        else
          "all"
        end
      end

      def organization_members
        return @organization_members if @organization_members

        # Grab public members first to see if we have at least enough for the preview.
        member_ids = profile_organization.public_members.order(:id).limit(SIDEBAR_MEMBERS_LIMIT).pluck(:id)

        # If we don't have enough and allow private members, add those
        if member_ids.size < SIDEBAR_MEMBERS_LIMIT && !profile_organization.limit_to_public_members?(viewer)
          member_ids.concat(profile_organization.member_ids(limit: SIDEBAR_MEMBERS_LIMIT))
        end

        @organization_members = ::User.where(id: member_ids).order(:id).limit(SIDEBAR_MEMBERS_LIMIT)
      end

      memoize def primary_avatar_url
        profile_organization.primary_avatar_url
      end

      memoize def profile_name
        profile_organization.profile_name
      end

      memoize def show_sponsor_button?
        return false unless GitHub.sponsors_enabled?

        sponsored_by_viewer? || sponsorable?
      end

      memoize def show_github_sponsor_recognition?
        GitHub.sponsors_enabled? && actively_sponsoring?
      end

      memoize def actively_sponsoring?
        profile_organization.sponsoring_count(include_private: member_or_billing_manager?) > 0
      end

      memoize def member_or_billing_manager?
        profile_organization.member?(viewer) || profile_organization.billing_manager?(viewer)
      end

      memoize def ghas_trial_banner_display_mode
        show_advanced_security_entrypoint?(organization: profile_organization, user: viewer)
      end

      memoize def show_ghas_trial_upsell_banner?
        ghas_trial_banner_display_mode != :do_not_show
      end

      memoize def show_developer_program_member_badge?
        !GitHub.enterprise? && profile_organization.developer_program_member?
      end

      memoize def site_admin_alerts
        layout_data_profile_organization = LayoutDataProfileOrganization.new(
          profile_organization: profile_organization,
          viewer: viewer,
        )

        if layout_data_profile_organization.show_admin_alerts?
          layout_data_profile_organization.site_admin_alerts
        end
      end

      memoize def sponsorable?
        profile_organization.sponsorable?
      end

      memoize def sponsored_by_viewer?
        profile_organization.sponsored_by_viewer?(viewer)
      end

      def user_or_organization_restricted?
        profile_organization.has_full_trade_restrictions?
      end

      memoize def visible_to_viewer_repository_count
        profile_organization.visible_repositories_for(viewer).size
      end

      class LayoutDataProfileOrganization
        include UsersHelper

        attr_reader :current_user, :this_user

        def initialize(profile_organization:, viewer:)
          @this_user = profile_organization
          @current_user = viewer
        end
      end
    end
  end
end
