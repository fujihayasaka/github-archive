# typed: true
# frozen_string_literal: true

module Organizations
  class Teams::TeamSettingsSidebarComponent < ApplicationComponent

    renders_one :settings_page

    attr_reader :org_login, :team_slug

    def initialize(org_login:, team_slug:, selected_link: nil)
      @org_login = org_login
      @team_slug = team_slug
      @selected_link = selected_link
    end
  end
end
