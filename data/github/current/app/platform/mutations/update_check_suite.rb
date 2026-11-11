# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateCheckSuite < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation
      include Platform::Helpers::CommitValidation

      description "Update a check suite"
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :check_suite_id, ID, "The node ID of the check suite.", required: true, loads: Objects::CheckSuite
      argument :artifacts, [Inputs::ArtifactData], "Details about collections of files produced by the run.", visibility: :internal, required: false
      argument :completed_log_url, String, "The URL to the completed logs.", visibility: :internal, required: false
      argument :conclusion, String, "Set the conclusion of this explicitly completed check suite", visibility: :internal, required: false
      argument :annotations, [Inputs::CheckAnnotationData], "The annotations that are made as part of the check suite.", visibility: :internal, required: false, default_value: []
      argument :concurrency, Inputs::Concurrency, "The concurency information about the check suite", visibility: :internal, required: false
      argument :external_id, String, "Used by integrators with which can create >1 check suite per sha to create suites idempotently", visibility: :internal, required: false

      error_fields

      field :check_suite, Objects::CheckSuite, "The updated check suite.", null: true

      extras [:execution_errors]

      resolve_tenant_context do |repo:, **_|
        _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(repo)
        Repositories::Public.resolve_tenant(id: repo_id)
      end

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_check_suite, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(check_suite:, repo:, execution_errors:, **inputs)
        if repo.id != check_suite.repository_id # effectively, a 404
          raise Platform::Errors::NotFound.new("Could not resolve check suite `#{check_suite.global_relay_id}` to repository `#{repo.global_relay_id}`")
        end

        unless allowed_to_modify_app?(app_id: check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_suite.global_relay_id}`")
        end

        annotations = inputs[:annotations] || []

        if annotations.size > Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST
          return {
            check_suite: nil,
            errors: [{
              path: %w[input annotations],
              message: "Annotations exceeds a maximum quantity of #{Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST}",
            }],
          }
        end

        if inputs[:artifacts]
          existing_source_urls = check_suite.artifacts.distinct.pluck(:source_url)
          new_artifacts = inputs[:artifacts]
            .map(&:to_h)
            .each do |artifact|
              artifact[:repository_id] = repo.id
              artifact[:workflow_run_id] = check_suite.workflow_run.id if check_suite.workflow_run.present?
            end
            # deduplication of artifacts by source_url to make this operation idempotent
            .reject { |artifact| existing_source_urls.include?(artifact[:source_url].to_s) }

          if !new_artifacts.empty?
            check_suite.artifacts.build(new_artifacts)
          end
        end

        check_suite.completed_log_url = inputs[:completed_log_url] if inputs[:completed_log_url]
        check_suite.external_id = inputs[:external_id] if inputs[:external_id]

        if check_suite.workflow_run.present? && inputs[:concurrency].present?
          unless Platform::Helpers::ViaActions.using_internal_schema?(context)
            raise Platform::Errors::Validation.new("You cannot set a check run with `concurrency`. `concurrency` is for internal use only.")
          end

          check_suite.status = "pending"
          concurrency_hash = inputs[:concurrency].to_h
          waiting_on_resource = concurrency_hash[:waiting_on_resource]

          if waiting_on_resource.present?
            waiting_on_resource[:check_run_id] = id_from_global_id(waiting_on_resource[:check_run_id])
            waiting_on_resource[:check_suite_id] = id_from_global_id(waiting_on_resource[:check_suite_id])
          end

          check_suite.workflow_run.update(concurrency: JSON.generate(concurrency_hash))
        end

        annotation_data = annotations.map do |annotation|
          annotation_attrs = Inputs::CheckAnnotationData.hash_from_input(annotation)
          annotation_attrs.merge({ repository_id: repo.id })
        end
        check_suite.annotations.build(annotation_data)

        if check_suite.save
          if inputs[:conclusion]
            check_suite.set_complete_explicitly!(inputs[:conclusion])
          end
          { check_suite: check_suite, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(check_suite, execution_errors)

          {
            check_suite: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(check_suite),
          }
        end
      end

      def id_from_global_id(global_id)
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] if global_id.present?
      end
    end
  end
end
