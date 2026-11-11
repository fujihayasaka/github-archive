# typed: true
# frozen_string_literal: true

module ArtifactRegistry
  class SidebarNavComponent < ApplicationComponent
    include GitHub::Memoizer

    DEFAULT_SELECTED_TAB = :github_packages
    SELECTED_TABS = [
      DEFAULT_SELECTED_TAB,
      :linked_artifacts,
    ]

    def initialize(
      organization:,
      selected_tab:
    )
      @org = organization
      @selected_tab = fetch_or_fallback(SELECTED_TABS, selected_tab)
    end
  end
end
