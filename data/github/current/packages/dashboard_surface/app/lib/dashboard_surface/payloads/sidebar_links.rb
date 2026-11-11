# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    # Shared sidebar link definitions and serialization.
    # The SidebarLink struct is used by all surfaces to define their sidebar navigation.
    # Each surface provides its own set of links (see IssuesDashboardSurface::Payloads::SidebarLinks).
    #
    # This is part of the shared dashboard surface infrastructure.
    class SidebarLinks
      class SidebarLink < T::Struct
        const :id, String
        const :query, String
        const :name, String
        const :icon, String
        const :color, String, default: "gray"
        const :source, String, default: "predefined"
        const :search_type, String, default: "pull-requests"
        const :path, String
      end

      # // !! CAUTION !! If you modify any 'query' field values here, they must also be updated in the UI implementation in the github/github-ui repo at: packages/dashboard-surface/helpers/query-resolver.ts
      sig { params(current_user: T.nilable(User)).returns(T::Array[SidebarLink]) }
      def self.links(current_user: nil)
        [
          SidebarLink.new(
            id: "inbox",
            query: "",
            name: "Inbox",
            icon: "inbox",
            path: "inbox"
          ),
          SidebarLink.new(
            id: "authored",
            query: Queries.authored_query_for(current_user),
            name: "Authored by me",
            icon: "smiley",
            path: "authored"
          ),
          SidebarLink.new(
            id: "assigned",
            query: Queries::ASSIGNED_QUERY,
            name: "Assigned to me",
            icon: "person",
            path: "assigned"
          ),
          SidebarLink.new(
            id: "involved",
            query: Queries::INVOLVES_QUERY,
            name: "Involves me",
            icon: "comment",
            path: "involves"
          ),
          SidebarLink.new(
            id: "review",
            query: Queries::REVIEW_QUERY,
            name: "Review requests",
            icon: "git_pull_request",
            path: "reviews"
          ),
        ]
      end

      sig { params(links: T::Array[SidebarLink]).returns(T::Array[T::Hash[String, String]]) }
      def self.serialize(links)
        links.map do |link|
          {
            "id" => link.id,
            "query" => link.query,
            "name" => link.name,
            "icon" => link.icon,
            "color" => link.color,
            "source" => link.source,
            "searchType" => link.search_type,
            "path" => link.path,
          }
        end
      end
    end
  end
end
