# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreatePullRequest < Platform::Mutations::Base
      description "Create a new pull request"

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, description: "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :base_ref_name, String, description: <<~DESCRIPTION, required: true
        The name of the branch you want your changes pulled into. This should be an existing branch
        on the current repository. You cannot update the base branch on a pull request to point
        to another repository.
      DESCRIPTION
      argument :head_ref_name, String, description: <<~DESCRIPTION, required: true
        The name of the branch where your changes are implemented. For cross-repository pull requests
        in the same network, namespace `head_ref_name` with a user like this: `username:branch`.
      DESCRIPTION
      argument :head_repository_id, ID, description: "The Node ID of the head repository.", required: false, loads: Objects::Repository
      argument :title, String, description: "The title of the pull request.", required: true
      argument :body, String, description: "The contents of the pull request.", required: false
      argument :maintainer_can_modify, Boolean, description: "Indicates whether maintainers can modify the pull request.", required: false, default_value: true
      argument :draft, Boolean, description: "Indicates whether this pull request should be a draft.", required: false, default_value: false
      error_fields
      field :pull_request, Objects::PullRequest, "The new pull request.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :create_pull_request, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(execution_errors:, repository:, **inputs)
        context[:permission].authorize_content(:pull_request, :create, repo: repository)

        if inputs[:base_ref_name].include?(":")
          raise Errors::Validation.new("The baseRefName is invalid.")
        end

        if inputs[:draft] && !repository.plan_supports?(:draft_prs)
          raise Errors::Unprocessable.new("Draft pull requests are not supported in this repository.")
        end

        head = inputs[:head_ref_name].b.sub(%r{refs/heads/}, "")
        base = inputs[:base_ref_name].b.sub(%r{refs/heads/}, "")

        if inputs[:head_repository].present?
          comparison = repository.comparison(
            base,
            head,
            head_repo: inputs[:head_repository]
          )
        else
          comparison = repository.comparison(
            base,
            head
          )
        end

        if inputs[:maintainer_can_modify] && disallow_fork_collab_access?(comparison: comparison, actor: context[:viewer])
          GitHub.logger.info("fork_collab access granted without head repo permissions", "gh.request_id": GitHub.context[:request_id])

          inputs[:maintainer_can_modify] = false
        end

        pull = PullRequest.create_for(repository,
            comparison: comparison,
            user: context[:viewer],
            base: base,
            head: head,
            title: inputs[:title],
            body: inputs[:body],
            maintainer_can_modify: inputs[:maintainer_can_modify],
            draft: inputs[:draft],
          )

        if pull.persisted?
          check_and_report_non_branch_head(pull)
          pull.enqueue_mergeable_update

          {
            pull_request: pull,
            errors: [],
          }
        else
          model_error_response(pull, execution_errors)
        end
      rescue ActiveRecord::RecordInvalid => e
        model_error_response(e.record, execution_errors)
      end

      private

      def disallow_fork_collab_access?(comparison:, actor:)
        PullRequest::ForkCollabAccessViaIntegrationAuthorizer.new(actor: actor,
          head_repository: comparison.head_repo,
          base_repository: comparison.base_repo).disallow?
      end

      def model_error_response(pull_request, execution_errors)
        Platform::UserErrors.append_legacy_mutation_model_errors_to_context(pull_request, execution_errors)
        errors = Platform::UserErrors.mutation_errors_for_model(pull_request,
          translate: { base: :base_ref_name, base_ref: :base_ref_name, head: :head_ref_name, head_ref: :head_ref_name, fork_collab: :maintainer_can_modify },
        )

        # Don't report errors on dependent attributes
        ignored_attributes = %w(base_sha head_sha)
        errors.reject! { |error| ignored_attributes.include?(error[:attribute]) }

        { pull_request: nil, errors: errors }
      end

      def check_and_report_non_branch_head(pull)
        return if pull.head_repository.heads.read(pull.head_ref_name).exist?

        T.unsafe(self).log_data[:pull_request_non_branch_head] = pull.head
        err = ::PullRequest::NonBranchHeadError.new(pull.head)
        err.set_backtrace(caller)
        Failbot.report_user_error(err,
          "gh.pull_request.head_repo.id": pull.head_repository.id
        )
      end
    end
  end
end
