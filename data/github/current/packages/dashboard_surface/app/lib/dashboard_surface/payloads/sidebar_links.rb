# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
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
      def self.links(current_user = nil)
        pulls_add_archived_false = T.let(FeatureFlag.vexi.enabled?(:pulls_add_archived_false, current_user, default: false), T::Boolean)
        add_updated_desc = T.let(FeatureFlag.vexi.enabled?(:dashboard_add_updated_desc, current_user, default: false), T::Boolean)

        all_links = [
          SidebarLink.new(
            id: "inbox",
            query: "",
            name: "Inbox",
            icon: "inbox",
            path: ""
          ),
          SidebarLink.new(
            id: "authored",
            query: build_query("is:pr author:@me state:open", pulls_add_archived_false, add_updated_desc),
            name: "Authored by me",
            icon: "smiley",
            path: "authored"
          ),
          SidebarLink.new(
            id: "assigned",
            query: build_query("is:pr assignee:@me state:open", pulls_add_archived_false, add_updated_desc),
            name: "Assigned to me",
            icon: "person",
            path: "assigned"
          ),
          SidebarLink.new(
            id: "involved",
            query: build_query("is:pr involves:@me state:open", pulls_add_archived_false, add_updated_desc),
            name: "Involves me",
            icon: "comment",
            path: "involves"
          ),
          SidebarLink.new(
            id: "agent",
            query: build_query("is:pr author:@copilot assignee:@me state:open", pulls_add_archived_false, add_updated_desc),
            name: "On my behalf",
            icon: "copilot",
            path: "on-my-behalf"
          ),
          SidebarLink.new(
            id: "review",
            query: build_query("is:pr review-requested:@me state:open", pulls_add_archived_false, add_updated_desc),
            name: "Review requests",
            icon: "git_pull_request",
            path: "reviews"
          ),
        ]

        if current_user && !FeatureFlag.vexi.enabled?(:pulls_dashboard_inbox, current_user, default: false)
          all_links.delete_if { |link| link.id == "inbox" }
        end

        all_links
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

      sig { params(base: String, add_archived_false: T::Boolean, add_updated_desc: T::Boolean).returns(String) }
      def self.build_query(base, add_archived_false, add_updated_desc)
        query = base
        query += " archived:false" if add_archived_false
        query += " sort:updated-desc" if add_updated_desc
        query
      end
    end
  end
end
