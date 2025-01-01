# typed: true
# frozen_string_literal: true

module Sidebar
  class ProjectPickerComponent < ApplicationComponent
    attr_reader :repository, :issue, :viewer, :access_level, :selected_tab, :tabs, :options

    ALLOWED_TABS = Set[:show_recent_projects_ui, :show_organization_projects_ui, :show_user_projects_ui, :show_repository_projects_ui]

    def initialize(issue:, repository: nil, viewer:, memex_enabled: false,
      access_level: "write", tabs_settings: {}, options: {})
      verify_tabs_settings(tabs_settings)

      @issue = issue
      @repository = repository || issue.repository
      @access_level = access_level
      @viewer = viewer
      @options = options

      suggester = ProjectSuggester.new(viewer: viewer, context: @repository, load_memex_projects: memex_enabled)


      # list of tabs to show depending on the current context [:recent, :repository, :organization, :user]
      @tabs = []
      @tabs << :recent if tabs_settings[:show_recent_projects_ui]
      @tabs << :repository if tabs_settings[:show_repository_projects_ui]
      @tabs << :organization if tabs_settings[:show_organization_projects_ui]
      @tabs << :user if tabs_settings[:show_user_projects_ui]

      @selected_tab = if tabs_settings[:show_recent_projects_ui] && suggester.recent_projects(min_permission_level: access_level).any?
        :recent
      elsif tabs_settings[:show_repository_projects_ui] && suggester.repository_projects(min_permission_level: access_level).any?
        :repository
      elsif tabs_settings[:show_organization_projects_ui] && suggester.organization_projects(min_permission_level: access_level).any?
        :organization
      elsif tabs_settings[:show_user_projects_ui] && suggester.user_projects(min_permission_level: access_level).any?
        :user
      else
        tabs.first
      end

    end

    private

    def verify_tabs_settings(tabs_settings)
      tabs_settings.each do |tab, _value|
        unless ALLOWED_TABS.include?(tab)
          raise ArgumentError, "Invalid tab: #{tab}"
        end
      end

      unless tabs_settings.values.reduce(:|)
        raise ArgumentError, "At least one tab should be visible"
      end
    end

  end
end
