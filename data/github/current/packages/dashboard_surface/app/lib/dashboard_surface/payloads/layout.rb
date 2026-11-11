# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    # Shared layout payload serializer for all dashboard surfaces.
    # Each surface (pulls, issues, repos) calls this with its own sidebar links,
    # saved views, and default view configuration.
    #
    # This is part of the shared dashboard surface infrastructure and will
    # eventually move to a `dashboard_surface_core` package.
    class Layout
      # `default_view_id` is either a known view slug (e.g. "inbox", "assigned")
      # or the stringified id of one of the user's saved views (a `SearchShortcut`).
      sig do
        params(
          compact_mode: T::Boolean,
          saved_views: T::Array[SavedView],
          sidebar_links: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink],
          sso: T::Hash[Symbol, T.untyped],
          default_view_id: String,
          filters: T::Hash[Symbol, T.untyped],
          selected_repos: T::Array[Repository],
          collapsed_sections: T::Array[String],
          section_order: T::Array[String],
          hidden_sections: T::Array[String],
        ).returns({
          compactMode: T::Boolean,
          savedViews: T::Array[SavedView],
          sidebarLinks: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink],
          sso: T::Hash[Symbol, T.untyped],
          selectedRepos: T::Array[Search::Helpers::RepoListPayloadHelper::PickerRepository],
          filters: T::Hash[Symbol, T.untyped],
          defaultViewId: String,
          collapsedSections: T::Array[String],
          sectionOrder: T::Array[String],
          hiddenSections: T::Array[String],
        })
      end
      def self.serialize(compact_mode:, saved_views:, sidebar_links:, sso:, default_view_id:, filters: {}, selected_repos: [], collapsed_sections: [], section_order: [], hidden_sections: [])
        {
          compactMode: compact_mode,
          savedViews: saved_views,
          sidebarLinks: sidebar_links,
          sso: sso,
          filters: filters,
          selectedRepos: Search::Helpers::RepoListPayloadHelper.serialize_repositories(selected_repos),
          defaultViewId: default_view_id,
          collapsedSections: collapsed_sections,
          sectionOrder: section_order,
          hiddenSections: hidden_sections,
        }
      end
    end
  end
end
