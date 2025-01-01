# typed: true
# frozen_string_literal: true

class Environments::BranchPoliciesController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_actions_environments_access
  before_action :ensure_can_use_environments
  before_action :ensure_branch_policies_enabled

  def create
    policy_type = params[:policy_type].present? ? params[:policy_type] : "branch"
    name = policy_type == "tag" ? GateBranchPolicy::PROTECTED_TAG_PREFIX + params[:name] : params[:name]
    new_branch_policy = branch_policy_gate.branch_policies.build(name: name, repository: current_repository)
    if new_branch_policy.save
      flash[:notice] = "Deployment #{policy_type} rule \"#{params[:name]}\" saved successfully."
    else
      flash[:error] = new_branch_policy.errors.first.full_message
    end
    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  def update
    policy_type = params[:policy_type].present? ? params[:policy_type] : "branch"
    name = policy_type == "tag" ? GateBranchPolicy::PROTECTED_TAG_PREFIX + params[:name] : params[:name]
    branch_policy.assign_attributes(name: name)

    if branch_policy.save
      flash[:notice] = "Deployment #{policy_type} rule \"#{branch_policy.name}\" updated successfully."
    else
      flash[:error] = branch_policy.errors.first.full_message
    end

    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  def destroy
    policy_type = branch_policy.is_tag_policy? ? "tag" : "branch"
    branch_policy.destroy
    flash[:notice] = "Deployment #{policy_type} rule \"#{branch_policy.name}\" removed."
    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  def type # rubocop:todo GitHub/UseRestfulActions
    notice_message = nil
    case params[:type]
    when "all-branches"
      environment.remove_branch_policy_gate
      notice_message = "all branches can deploy"
    when "protected-branches"
      environment.create_branch_policy_gate(protected_branch_policy: true)
      notice_message = "only protected branches can deploy"
    when "selected-branches"
      environment.create_branch_policy_gate(protected_branch_policy: false)
      notice_message = "only selected branches can deploy"
    when "selected-branches-and-tags"
      environment.create_branch_policy_gate(protected_branch_policy: false)
      notice_message = "only selected branches and tags can deploy"
    end
    if notice_message.nil?
      flash[:error] = "Environment changes failed to save: Unsupported branch policy type."
    else
      flash[:notice] = "Environment changes successfully saved: #{notice_message}."
    end
    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  private

  def branch_policy # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_branch_policy ||= branch_policy_gate.branch_policies.find(params[:id])
  end

  def branch_policy_gate
    environment.branch_policy_gate
  end

  def environment # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_environment ||= current_repository.environments.find(params[:environment_id])
  end

  def ensure_can_use_environments
    render_404 unless current_repository.can_use_environments?
  end

  def ensure_branch_policies_enabled
    render_404 unless current_repository.can_use_deployment_protected_branch?
  end
end
