# typed: false
# frozen_string_literal: true

class Api::Deployments < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist

  DEFAULT_ATTRIBUTES = %i(description environment payload ref task sha creator transient_environment production_environment)

  # List the latest deployments for a repository across all shas
  get "/repositories/:repository_id/deployments", operation_id: "repos/list-deployments" do
    control_access :list_deployments,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    filtered_options = params.slice("ref", "sha", "task", "environment").keep_if { |_k, v| v.present? }

    if GitHub.flipper[:deployments_pagination_optimization].enabled?(repo)
      # We do very a specific optimization using a subquery. That means pagination is
      # less straightforward than usual and we need to limit not the top-level query but the subquery.

      # Prep subquery and paginate it
      subquery = deployments_sub_query(repo, filtered_options)
      subquery = subquery.limit(pagination[:per_page]).page(pagination[:page])

      # Fetch deployments usign the subquery
      deployments = repo.deployments.from("deployments").joins("INNER JOIN (#{subquery.to_sql}) as d2 ON deployments.id = d2.id")

      # Update the paginator here (because the object we are delivering is missing a total_entries attribute)
      paginator.collection_size = subquery.unscoped.from(
        subquery.unscope(:order, :select).select("1 as one").limit(pagination[:total_entries]),
      ).count
    else
      subquery = deployments_sub_query(repo, filtered_options)
      deployments = paginate_rel(repo.deployments.from("deployments").joins("INNER JOIN (#{subquery.to_sql}) as d2 ON deployments.id = d2.id"))
    end

    GitHub::PrefillAssociations.prefill_associations(deployments, [:creator, :repository], available_records: [repo])
    deliver :deployment_hash, deployments, repo: repo
  end

  def deployments_sub_query(repo, filtered_options)
    repo.deployments.from("`deployments` IGNORE INDEX FOR ORDER BY (PRIMARY)").where(filtered_options).select(:id).order(id: :desc)
  end

  # Create a deployment event for a repository at a specific ref.
  post "/repositories/:repository_id/deployments", operation_id: "repos/create-deployment" do
    control_access :write_deployment,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("deployment", "create-legacy")
    attrs = [:auto_merge, :required_contexts, :description, :environment, :payload, :ref, :task]
    attrs.concat([:transient_environment, :production_environment])
    data = attr(data, *attrs)

    commit  = find_ref(repo, data["ref"])
    payload = data["payload"]

    data["sha"]          = commit.oid
    data["creator"]      = current_user
    data["payload"]      = GitHub::JSON.encode(payload) if payload

    if data["environment"] == "production" && data["production_environment"].nil?
      data["production_environment"] = true
    end

    auto_merge        = data.delete("auto_merge")
    required_contexts = data.delete("required_contexts")

    deployment = repo.deployments.build(attr(data, *DEFAULT_ATTRIBUTES))

    deployment.auto_merge        = auto_merge
    deployment.required_contexts = required_contexts

    if integration_user_request?
      deployment.performed_via_integration = current_integration
    end

    if deployment.auto_merge?
      message = "Auto-merged #{repo.default_branch} into #{deployment.ref} on deployment."
      options = {
        reflog_data: request_reflog_data("auto-merge deployment api"),
        commit_message: message,
      }
      if deployment.merge_for(current_user, options)
        deliver_raw({ message: message }, status: 202)
      else
        deliver_error(409,
          message: "Conflict merging #{repo.default_branch} into #{deployment.ref}.")
      end
    elsif deployment.failed_commit_statuses?
      validation_error = api_error(:Deployment, :required_contexts, :invalid,
                                   contexts: deployment.combined_status_contexts)

      deliver_error 409, errors: [validation_error],
        message: "Conflict: Commit status checks failed for #{deployment.ref}."
    else
      if deployment.save
        deliver :deployment_hash, deployment, repo: repo, status: 201,
          last_modified: calc_last_modified_for_object(deployment)
      else
        deliver_error 422, errors: deployment.errors
      end
    end
  end

  # Find a specific deployment for a repository
  get "/repositories/:repository_id/deployments/:deployment_id", operation_id: "repos/get-deployment" do
    control_access :read_deployment, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    deployment = repo.deployments.find_by(id: int_id_param!(key: :deployment_id))
    record_or_404(deployment)

    deliver :deployment_hash, deployment, repo: repo,
      last_modified: calc_last_modified_for_object(deployment)
  end

  # Delete a specific deployment for a repository
  delete "/repositories/:repository_id/deployments/:deployment_id", operation_id: "repos/delete-deployment" do
    receive_with_schema("deployment", "delete")

    repo = find_repo!
    control_access :delete_deployment,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    deployment = repo.deployments.find_by(id: int_id_param!(key: :deployment_id))
    record_or_404(deployment)

    deployments_count = repo.deployments.where(environment: deployment.environment).count
    if deployment.active? && deployments_count > 1
      deliver_error 422, errors: ["We cannot delete an active deployment unless it is the only deployment in a given environment."]
    else
      deployment.destroy!
      deliver_empty(status: 204)
    end
  end

  def find_ref(repo, ref)
    if ref && commit_oid = repo.ref_to_sha(ref)
      Repositories.domain.commits.by_oid(repository: repo, commit_oid: commit_oid)
    else
      deliver_error!(422, message: "No ref found for: #{ref}")
    end
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    deliver_error!(422, message: "No ref found for: #{ref}")
  end
end
