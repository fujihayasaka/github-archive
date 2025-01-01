# typed: true
# frozen_string_literal: true

class Api::DeploymentBranchPolicies < Api::App

  # Gets a list of all gate protection rules single deployment branch gate
  get "/repositories/:repository_id/environments/:environment/deployment-branch-policies", operation_id: "repos/list-deployment-branch-policies" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_deployment_protected_branch?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    environment = repo.environments.includes(:gates).find_by(name: params[:environment])
    deliver_error! 404 unless environment.present? && environment.branch_policy_gate.present? && !environment.branch_policy_gate_branch_protected?

    branch_policies = paginate_rel(environment.branch_policy_gate.branch_policies)

    deliver :deployment_branch_policies_hash, { branch_policies: branch_policies, total_count: branch_policies.total_entries }
  end

  # Get or create a deployment branch gate
  post "/repositories/:repository_id/environments/:environment/deployment-branch-policies", operation_id: "repos/create-deployment-branch-policy" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_deployment_protected_branch?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    environment = repo.environments.find_by(name: params[:environment])
    deliver_error! 404 unless environment.present? && environment.branch_policy_gate.present? && !environment.branch_policy_gate_branch_protected?

    data = receive_with_schema("deployment-branch-policy", "create-deployment-branch-policy")
    name = data["type"] == "tag" ? GateBranchPolicy::PROTECTED_TAG_PREFIX + data["name"] : data["name"]

    branch_policy = environment.branch_policy_gate.branch_policies.find_by(name: name, gate_id: environment.branch_policy_gate.id)

    redirect request.path_info, 303 unless branch_policy.nil? # Redirect to same path, but the redirect should end up in a GET

    new_branch_policy = environment.branch_policy_gate.branch_policies.build(name: name, repository_id: params[:repository_id])

    deliver_error!(422, message: new_branch_policy.errors.full_messages.to_sentence) unless new_branch_policy.save

    deliver :deployment_branch_policy_hash, new_branch_policy
  end

  # Gets a single deployment branch gate
  get "/repositories/:repository_id/environments/:environment/deployment-branch-policies/:branch_policy_id", operation_id: "repos/get-deployment-branch-policy" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_deployment_protected_branch?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    environment = repo.environments.includes(:gates).find_by(name: params[:environment])
    deliver_error! 404 unless environment.present? && environment.branch_policy_gate.present? && !environment.branch_policy_gate_branch_protected?
    branch_policy = environment.branch_policy_gate.branch_policies.find_by(id: params[:branch_policy_id])
    deliver_error! 404 unless branch_policy.present?

    deliver :deployment_branch_policy_hash, branch_policy
  end

  # Edit a deployment branch gate
  put "/repositories/:repository_id/environments/:environment/deployment-branch-policies/:branch_policy_id", operation_id: "repos/update-deployment-branch-policy" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_deployment_protected_branch?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    environment = repo.environments.includes(:gates).find_by(name: params[:environment])
    deliver_error! 404 unless environment.present? && environment.branch_policy_gate.present? && !environment.branch_policy_gate_branch_protected?
    branch_policy = environment.branch_policy_gate.branch_policies.find_by(id: params[:branch_policy_id])
    deliver_error! 404 unless branch_policy.present?

    data = receive_with_schema("deployment-branch-policy", "edit-deployment-branch-policy")
    name = branch_policy.is_tag_policy? ? GateBranchPolicy::PROTECTED_TAG_PREFIX + data["name"] : data["name"]
    branch_policy.assign_attributes(name: name)

    deliver_error!(422, message: branch_policy.errors.full_messages.to_sentence) unless branch_policy.save

    deliver :deployment_branch_policy_hash, branch_policy
  end

  # Deletes a deployment branch policies
  delete "/repositories/:repository_id/environments/:environment/deployment-branch-policies/:branch_policy_id", operation_id: "repos/delete-deployment-branch-policy" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_deployment_protected_branch?

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    environment = repo.environments.includes(:gates).find_by(name: params[:environment])
    deliver_error! 404 unless environment.present? && environment.branch_policy_gate.present? && !environment.branch_policy_gate_branch_protected?
    branch_policy = environment.branch_policy_gate.branch_policies.find_by(id: params[:branch_policy_id])
    deliver_error! 404 unless branch_policy.present?

    branch_policy.destroy

    deliver_empty(status: 204)
  end
end
