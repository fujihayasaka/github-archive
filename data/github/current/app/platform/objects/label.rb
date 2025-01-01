# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Label < Platform::Objects::Base
      description "A label for categorizing Issues, Pull Requests, Milestones, or Discussions with a given Repository."

      include Platform::Authorization::ReauthorizeScopedObjects

      implements_node templates: [[:rl, :repo_id, :label_id]], as: "LA", ready_date: Platform::Helpers::GlobalId::COHORT_4 do |label|
        {
          prefix: :rl,
          repo_id: label.repository_id,
          label_id: label.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, label)
        permission.async_repo_and_org_owner(label).then do |repo, org|
          permission.access_allowed?(:get_repo_label, resource: label, repo: repo, allow_integrations: true, current_org: org, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      field :name, String, "Identifies the label name.", null: false
      field :description, String, "A brief description of this label.", null: true

      field :name_html, String, "Identifies the label name, rendered to HTML.", visibility: :internal, null: false

      def name_html
        @object.async_name_html
      end

      field :color, String, "Identifies the label color.", null: false
      field :updated_at, Scalars::DateTime, "Identifies the date and time when the label was last updated.", null: true
      field :created_at, Scalars::DateTime, "Identifies the date and time when the label was created.", null: true

      field :repository, Repository, method: :async_repository, description: "The repository associated with this label.", null: false

      field :issues, resolver: Resolvers::Issues, description: "A list of issues associated with this label."

      # The db query that fetches totalCount of issues is not optimized enough for labels that has too many issues.
      # Therefore we are adding a separate field to return the count of issues associated with this label.
      field :issue_count, Integer, "The number of issues associated with this label.", null: true, visibility: :internal
      def issue_count
        @object.issues_without_pull_requests_count.to_i # domain-isolation-query-violation:ignore:packages/issues (select)
      end

      # The db query that fetches totalCount of pull requests is not optimized enough for labels that has too many pull requests.
      # Therefore we are adding a separate field to return the count of pull requests associated with this label.
      field :pull_request_count, Integer, "The number of pull requests associated with this label.", null: true, visibility: :internal
      def pull_request_count
        @object.pull_requests_count.to_i # domain-isolation-query-violation:ignore:packages/issues (select)
      end

      field :pull_requests, resolver: Resolvers::LabelPullRequests, description: "A list of pull requests associated with this label."

      url_fields description: "The HTTP URL for this label." do |label|
        label.async_path_uri
      end

      field :is_default, Boolean, "Indicates whether or not this is a default label.", method: :default?, null: false
    end
  end
end
