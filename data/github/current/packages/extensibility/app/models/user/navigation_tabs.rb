# typed: true
# frozen_string_literal: true

class User
  class NavigationTabs
    include GitHub::Memoizer

    include NavigationTabsInterface

    include ProfilesHelper
    include UrlHelpers
    include UrlHelper

    def self.for(user:, **opts)
      new(user, **opts).tabs
    end

    attr_reader :user, :current_user, :layout_data, :private_profile_override
    alias :private_profile_override? :private_profile_override

    def initialize(user, private_profile_override: false, **opts)
      @user = user
      @current_user = opts[:current_user]
      @private_profile_override = private_profile_override

      @layout_data = Profiles::User::LayoutData.new(
        profile_user: user,
        viewer: current_user,
        active_tab: nil,
      )
    end

    def tabs
      if user.private_profile_for?(current_user) && !private_profile_override?
        [
          overview_tab,
          repositories_tab
        ].compact
      else
        [
          overview_tab,
          repositories_tab,
          projects_tab,
          packages_tab,
          stars_tab,
          sponsoring_tab,
        ].compact
      end
    end

    def overview_tab
      Site::Header::UnderlineNavTab.new(
        text: "Overview",
        icon: :book,
        href: user_path(user),
        highlight: :overview,
        highlight_opts: { disqualifying_params: [:tab] },
        data: tab_attrs("overview")
      )
    end

    def repositories_tab
      profile_tab(:repositories, text: "Repositories", icon: :repo, count: layout_data.repository_count)
    end

    def projects_tab
      return if current_user && !current_user.user_projects_enabled?
      profile_tab(:projects, text: "Projects", icon: :table, count: layout_data.open_public_projects_count)
    end

    def packages_tab
      return unless packages_tab_enabled?
      profile_tab(:packages, text: "Packages", icon: :package, count: layout_data.packages_count)
    end

    def stars_tab
      profile_tab(:stars, text: "Stars", icon: :star, count: layout_data.stars_count)
    end

    def sponsoring_tab
      return unless sponsoring_tab_enabled?
      profile_tab(:sponsoring, text: "Sponsoring", icon: :heart, count: layout_data.sponsoring_count)
    end

    def popover; end
    def tab_counts_url; end

    private

    def profile_tab(tab_name, text:, icon:, count: nil)
      Site::Header::UnderlineNavTab.new(
        text: text,
        icon: icon,
        count: count,
        href: user_path(user, params: { tab: tab_name }),
        data: tab_attrs(tab_name.to_s),
        highlight: tab_name.to_s,
        highlight_opts: {
          include_params: { tab: tab_name.to_s }
        },
      )
    end

    def tab_attrs(tab_name)
      profile_click_tracking_attrs(
        :"TAB_#{tab_name.upcase}",
        current_user_id: current_user.id,
        profile_user_id: user.id
      ).merge("tab-item" => tab_name)
    end

    memoize def sponsoring_tab_enabled?
      GitHub.sponsors_enabled? && layout_data.active_and_inactive_sponsoring_count.positive?
    end

    memoize def packages_tab_enabled?
      PackageRegistryHelper.show_packages?
    end
  end
end
