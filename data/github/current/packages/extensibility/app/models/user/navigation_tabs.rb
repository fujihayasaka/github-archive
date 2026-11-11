# typed: true
# frozen_string_literal: true

class User
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include GitHub::Memoizer

    include NavigationTabsInterface

    include ProfilesHelper
    include UrlHelpers
    include UrlHelper

    TAB_METADATA = {
      overview: {
        icon: "book",
        label: "Overview",
      },
      repositories: {
        icon: "repo",
        label: "Repositories",
        highlight: [:repositories],
      },
      projects: {
        icon: "table",
        label: "Projects",
        highlight: [:projects],
      },
      packages: {
        icon: "package",
        label: "Packages",
        highlight: [:packages],
      },
      stars: {
        icon: "star",
        label: "Stars",
        highlight: [:stars, :user_lists],
      },
      sponsoring: {
        icon: "heart",
        label: "Sponsoring",
        highlight: [:sponsoring],
      },
    }.freeze

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
      record_tab_timing(:overview) do
        meta = TAB_METADATA[:overview]
        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: user_path(user),
          highlight: :overview,
          highlight_opts: { disqualifying_params: [:tab] },
          data: tab_attrs("overview")
        )
      end
    end

    def repositories_tab
      record_tab_timing(:repositories) do
        profile_tab(:repositories, count: layout_data.repository_count)
      end
    end

    def projects_tab
      record_tab_timing(:projects) do
        return if current_user && !current_user.user_projects_enabled?
        profile_tab(:projects, count: layout_data.open_public_projects_count)
      end
    end

    def packages_tab
      record_tab_timing(:packages) do
        return unless packages_tab_enabled?
        profile_tab(:packages, count: layout_data.packages_count)
      end
    end

    def stars_tab
      record_tab_timing(:stars) do
        profile_tab(:stars, count: layout_data.stars_count)
      end
    end

    def sponsoring_tab
      record_tab_timing(:sponsoring) do
        return unless sponsoring_tab_enabled?
        profile_tab(:sponsoring, count: layout_data.sponsoring_count)
      end
    end

    def turbo_frame
      "user-profile-frame"
    end

    def popover; end
    def tab_counts_url; end

    private

    def profile_tab(tab_name, count: nil)
      meta = TAB_METADATA[tab_name]

      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        count: count,
        href: user_path(user, params: { tab: tab_name }),
        data: tab_attrs(tab_name.to_s),
        highlight: meta[:highlight],
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

    def entity_name
      "user"
    end
  end
end
