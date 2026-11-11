# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  module Payloads
    class SidebarLinks
      sig { returns(T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink]) }
      def self.links
        [
          DashboardSurface::Payloads::SidebarLinks::SidebarLink.new(
            id: "assigned",
            query: Queries::ASSIGNED_QUERY,
            name: "Assigned to me",
            icon: "person",
            search_type: "issues",
            path: "assigned",
          ),
          DashboardSurface::Payloads::SidebarLinks::SidebarLink.new(
            id: "created",
            query: Queries::CREATED_QUERY,
            name: "Created by me",
            icon: "smiley",
            search_type: "issues",
            path: "created",
          ),
          DashboardSurface::Payloads::SidebarLinks::SidebarLink.new(
            id: "mentioned",
            query: Queries::MENTIONED_QUERY,
            name: "Mentioning me",
            icon: "mention",
            search_type: "issues",
            path: "mentioned",
          ),
          DashboardSurface::Payloads::SidebarLinks::SidebarLink.new(
            id: "recent",
            query: Queries::RECENT_QUERY,
            name: "Recently updated",
            icon: "clock",
            search_type: "issues",
            path: "recent",
          ),
        ]
      end
    end
  end
end
