# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReviewRequest < Platform::Objects::Base
      description "A request for a user to review a pull request."

      implements_node templates: [[:rrr, :repo_id, :review_request_id]], as: "RR", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |review_request|
        review_request.async_pull_request.then do |pull_request|
          {
            prefix: :rrr,
            repo_id: pull_request.repository_id,
            review_request_id: review_request.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, review_request)
        permission.load_pull_and_issue(review_request).then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:get_pull_request_review_request, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_pull_request(object)
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :requested_reviewer, Unions::RequestedReviewer, description: "The reviewer that is requested.", null: true

      def requested_reviewer
        @object.async_reviewer.then do |reviewer|
          unless reviewer.nil?
            reviewer_type = Helpers::NodeIdentification.type_name_from_object(reviewer)
            @context[:permission].typed_can_see?(reviewer_type, reviewer).then do |can_read|
              reviewer if can_read
            end
          end
        end
      end

      field :requested_by, Objects::User, description: "The user who triggered this request for review.", mobile_only: true, null: true

      def requested_by
        @object.async_pull_request.then do |pull|
          pull.async_user_requesting(@context[:viewer])
        end
      end

      field :pull_request, Objects::PullRequest, method: :async_pull_request, description: "Identifies the pull request associated with this review request.", null: false

      field :as_code_owner, Boolean, method: :async_as_codeowner?, description: "Whether this request was created for a code owner", null: false

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for codeOwnerUrl.
      field :code_owners_resource_path, Scalars::URI, visibility: :internal, method: :async_codeowners_path_uri, description: "The HTTP URL to the codeowner file and line location.", null: true

      field :code_owners_file, Objects::CommittishFile, visibility: :internal, method: :async_codeowners_file, description: "Identifies the code owner file causing the review request", null: true

      field :assigned_from_review_request, Objects::ReviewRequest, visibility: :under_development, method: :async_assigned_from_review_request, description: "The original review request that assigned this review request, if present.", null: true
    end
  end
end
