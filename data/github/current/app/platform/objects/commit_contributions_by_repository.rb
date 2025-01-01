# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommitContributionsByRepository < Platform::Objects::Base
      description "This aggregates commits made by a user within one repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, obj)
        permission.typed_can_access?("Repository", obj.repository)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end


      scopeless_tokens_as_minimum

      url_fields description: "The HTTP URL for the user's commits to the repository in this time range." do |contribs_by_repo|
        path = "/{owner}/{repo}/commits?author={author}&since={since}&until={until}"
        time_range = contribs_by_repo.time_range
        repo = contribs_by_repo.repository

        repo.async_owner.then do |owner|
          template_args = {
            owner: owner.display_login,
            repo: repo.name,
            author: contribs_by_repo.user.display_login,
            since: time_range.begin.beginning_of_day.utc.to_date.iso8601,
            until: (time_range.end.beginning_of_day + 1.day).utc.to_date.iso8601,
          }

          Addressable::Template.new(path).expand(template_args)
        end
      end

      field :repository, Repository,
        description: "The repository in which the commits were made.", null: false

      field :contributions, Connections::CreatedCommitContribution,
        description: "The commit contributions, each representing a day.", null: false do
        argument :order_by, Inputs::CommitContributionOrder,
          "Ordering options for commit contributions returned from the connection.",
          required: false,
          default_value: { field: "occurred_at", direction: "DESC" }
      end

      def contributions(order_by: nil)
        result = @object.contributions(order_by: order_by)
        ArrayWrapper.new(result)
      end
    end
  end
end
