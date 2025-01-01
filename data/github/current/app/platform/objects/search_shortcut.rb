# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcut < Platform::Objects::Base
      description "A shortcut for a search with specified filters"
      scopeless_tokens_as_minimum
      mobile_only true

      implements_node templates: [[:ssc, :search_shortcut_id]], as: "SSC", ready_date: "1970-01-01" do |search_shortcut|
        {
          prefix: :ssc,
          search_shortcut_id: search_shortcut.id,
        }
      end

      implements Interfaces::Shortcutable
      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_dashboard.then do |dashboard|
          dashboard.async_user.then do |user|
            permission.access_allowed?(
              :read_user_dashboard,
              resource: user,
              current_repo: nil,
              current_org: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_dashboard.then do |dashboard|
          dashboard.async_user.then do |user|
            permission.viewer == user
          end
        end
      end

      def scoping_repository
        Loaders::ActiveRecord.load(::Repository, object.scoping_repository_id, security_violation_behaviour: :nil)
      end
    end
  end
end
