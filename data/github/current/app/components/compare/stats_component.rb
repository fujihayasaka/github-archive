# typed: true
# frozen_string_literal: true

module Compare
  class StatsComponent < ApplicationComponent
    include HydroHelper

    attr_reader :author_count, :commit_count, :selected_tab, :comparison

    def initialize(comparison:, author_count:, commit_count:, selected_tab:)
      @comparison = comparison
      @diffs = comparison.diffs
      @author_count = author_count
      @commit_count = commit_count
      @selected_tab = selected_tab
    end

    def render_tabs?
      @selected_tab.present?
    end

    def files_changed_count
      @diffs.available? ? @diffs.changed_files : Float::INFINITY
    end

    def set_class(tab_name)
      class_string = "tabnav-tab js-compare-tab"
      class_string += " selected" if tab_name == @selected_tab
      class_string
    end

    memoize def commits_hydro_attributes
      click_tracking_attributes("commits_tab")
    end

    memoize def files_hydro_attributes
      click_tracking_attributes("files_tab")
    end

    def click_tracking_attributes(action)
      payload = {
        user_id: current_user&.id,
        repository_id: comparison.base_repo&.id,
        category: "compare_show",
        data: comparison.click_tracking_attributes,
        action: action
      }
      hydro_click_tracking_attributes("pull_request.user_action", payload)
    end
  end
end
