# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    class Layout
      sig do
        params(
          compact_mode: T::Boolean,
          saved_views: T::Array[SavedView],
          sidebar_links: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink],
          sso: T::Hash[Symbol, T.untyped],
        ).returns({
          compactMode: T::Boolean,
          savedViews: T::Array[SavedView],
          sidebarLinks: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink],
          sso: T::Hash[Symbol, T.untyped],
        })
      end
      def self.serialize(compact_mode:, saved_views:, sidebar_links:, sso:)
        {
          compactMode: compact_mode,
          savedViews: saved_views,
          sidebarLinks: sidebar_links,
          sso: sso,
        }
      end
    end
  end
end
