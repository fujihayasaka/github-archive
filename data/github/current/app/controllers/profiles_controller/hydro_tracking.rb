# typed: true
# frozen_string_literal: true

class ProfilesController
  class HydroTracking
    TAB_PARAM_TO_ENUM = {
      nil => :OVERVIEW,
      "followers" => :FOLLOWERS,
      "following" => :FOLLOWING,
      "overview" => :OVERVIEW,
      "packages" => :PACKAGES,
      "repositories" => :REPOSITORIES,
      "stars" => :STARS,
    }.freeze

    def initialize(
      profile_user:,
      profile_viewer:,
      scoped_organization:,
      tab_param:,
      profile_readme_rendered:
    )
      @profile_user = profile_user
      @profile_viewer = profile_viewer
      @scoped_organization = scoped_organization
      @tab_param = tab_param
      @profile_readme_rendered = profile_readme_rendered
    end

    def publish_user_profile_page_view
      return if profile_user.organization?

      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: profile_user.organizations.any?,
        profile_user: profile_user,
        profile_viewer: profile_viewer,
        profile_readme_rendered: profile_readme_rendered,
        scoped_org_id: scoped_organization&.id,
        selected_tab: selected_tab_enum_value,
      )
    end

    private

    attr_reader :profile_user, :profile_viewer, :scoped_organization, :tab_param,
      :profile_readme_rendered

    def selected_tab_enum_value
      TAB_PARAM_TO_ENUM.fetch(tab_param, :UNKNOWN)
    end
  end
end
