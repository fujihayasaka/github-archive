# typed: false
# frozen_string_literal: true

module Actions::PolicyHelper
  def set_fork_pr_workflows_policy(entity, form_policy)
    if form_policy["run_workflows"]
      policy = Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS
      policy |= Configurable::ForkPrWorkflowsPolicy::WRITE_TOKENS if form_policy["write_tokens"]
      policy |= Configurable::ForkPrWorkflowsPolicy::SEND_SECRETS if form_policy["send_secrets"]
      entity.set_fork_pr_workflows_policy(policy: policy, actor: current_user)

      if set_approvals_policy?(form_policy)
        approvals_policy = form_policy["require_approvals"] ? Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS : Configurable::ActionsPrivateForkPrApprovals::NONE
        entity.set_actions_private_fork_pr_approvals_policy(policy: approvals_policy, actor: current_user)
      end
    else
      entity.disable_fork_pr_workflows(actor: current_user)

      if set_approvals_policy?(form_policy)
        entity.set_actions_private_fork_pr_approvals_policy(policy: Configurable::ActionsPrivateForkPrApprovals::NONE, actor: current_user)
      end
    end

    if entity.errors.any?
      flash[:error] = "Error saving your changes: #{entity.errors.full_messages.to_sentence}"
      redirect_to :back
    else
      flash[:notice] = "Fork pull request workflow settings saved."
      redirect_to :back
    end
  rescue Configurable::ForkPrWorkflowsPolicy::Error, Configurable::ActionsPrivateForkPrApprovals::Error
    flash[:error] = "Error saving your changes."
    redirect_to :back
  end

  def set_public_fork_pr_workflows_policy(entity, form_policy)
    #default
    policy = Configurable::PublicForkPrWorkflowsPolicy::RUN_WORKFLOWS
    policy |= Configurable::PublicForkPrWorkflowsPolicy::SEND_VARIABLES if form_policy["send_variables"]
    entity.set_public_fork_pr_workflows_policy(policy: policy, actor: current_user)

    if entity.errors.any?
      flash[:error] = "Error saving your changes: #{entity.errors.full_messages.to_sentence}"
      redirect_to :back
    else
      if !entity.is_a?(Repository)
        flash[:notice] = "Public fork pull request workflow settings saved."
      else
        flash[:notice] = "Fork pull request workflow settings saved."
      end
      redirect_to :back
    end
  rescue Configurable::PublicForkPrWorkflowsPolicy::Error
    flash[:error] = "Error saving your changes."
    redirect_to :back
  end

  # This replaces the default `set_default_workflow_permissions` method
  # under feature flag for https://github.com/github/c2c-actions-policy/issues/215
  # adds saving for can approve PR within same action
  def set_default_and_approval_workflow_permissions(entity, wf_default, wf_pr_approve)
    entity.set_default_workflow_permissions(wf_default, current_user)

    if wf_pr_approve == {} || wf_pr_approve == "0"
      sanitized_wf_pr_approve = false
    elsif wf_pr_approve == "on" || wf_pr_approve == "1"
      sanitized_wf_pr_approve = true
    else
      # error will be handled in set_actions_workflow_permission_can_approve_pr
      sanitized_wf_pr_approve = wf_pr_approve
    end
    entity.set_actions_workflow_permission_can_approve_pr(sanitized_wf_pr_approve, current_user)

    if entity.errors.any?
      flash[:error] = "Error saving your changes: #{entity.errors.full_messages.to_sentence}"
      redirect_to :back
    else
      flash[:notice] = "Default workflow permissions settings saved."
      redirect_to :back
    end
  rescue Configurable::DefaultWorkflowPermissions::Error => err
    flash[:error] = "Error saving your changes. #{err.message}"
    redirect_to :back
  end

  def set_actions_fork_pr_approvals_policy(entity, form_policy)
    entity.set_actions_fork_pr_approvals_policy(policy: form_policy, actor: current_user)

    if entity.errors.any?
      flash[:error] = "Error saving your changes: #{entity.errors.full_messages.to_sentence}"
      redirect_to :back
    else
      flash[:notice] = "Fork pull request outside collaborators settings saved."
      redirect_to :back
    end
  rescue ArgumentError => err
    flash[:error] = "Sorry, there was an issue updating your settings."
    redirect_to :back
  end

  def set_actions_repository_share_policy(entity, form_policy)
    entity.set_actions_repository_share_policy(policy: form_policy, actor: current_user)

    if entity.errors.any?
      flash[:error] = "Error saving your changes: #{entity.errors.full_messages.to_sentence}"
      redirect_to :back
    else
      flash[:notice] = "Repository actions access settings saved."
      redirect_to :back
    end
  rescue ArgumentError, Configurable::ActionsRepositorySharePolicy::NotApplicableError => err
    flash[:error] = "Sorry, there was an issue updating your settings."
    redirect_to :back
  end

  def set_approvals_policy?(form_policy)
    return true if form_policy["require_approvals"]

    # Don't set the policy if the input element was disabled or not rendered
    !form_policy["require_approvals_setting_excluded"]
  end
end
