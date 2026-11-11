# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestUserPreferences < Platform::Objects::Base
      visibility :internal
      description "Represents the user's preferences for a pull request"
      minimum_accepted_scopes ["user"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_see?("User", object.user)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer == object.user
      end

      field :diff_view, String, "The user's preferred diff view, split or unified", null: false
      field :ignore_whitespace, Boolean, "Whether the user has chosen to ignore whitespace in diffs in a pull request", null: true do
        argument :pull_request_id, ID, "The pull request to check for ignore whitespace", required: false
      end

      def ignore_whitespace(pull_request_id: nil)
        if @object.pull_request
          @object.ignore_whitespace
        elsif @object.user == @context[:viewer] && pull_request_id
          Helpers::NodeIdentification.async_typed_object_from_id([::Platform::Objects::PullRequest], pull_request_id, context).then do |pull_request|
            Promise.all([pull_request.async_repository, pull_request.async_issue]).then do
              pull_request.ignore_whitespace?(@context[:viewer])
            end
          end
        else
          nil
        end
      end

      field :tab_size, Int, "The user's preferred tab size", null: false
    end
  end
end
