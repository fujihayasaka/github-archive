# typed: true
# frozen_string_literal: true

module Api::App::ActionsForkPrWorkflowHelper
  extend T::Helpers

  requires_ancestor { Api::App }

  # Map API parameters to the internal format used by the policy setter
  def map_fork_pr_workflows_params(data)
    {
      "run_workflows" => data["run_workflows_from_fork_pull_requests"],
      "write_tokens" => data["send_write_tokens_to_workflows"],
      "send_secrets" => data["send_secrets_and_variables"],
      "require_approvals" => data["require_approval_for_fork_pr_workflows"]
    }
  end

  def set_fork_pr_workflows_policy(entity, form_policy)
    if form_policy["run_workflows"]
      # current policy to preserve unspecified settings
      current_policy = entity.fork_pr_workflows_policy || 0

      # build new policy
      policy = Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS

      if form_policy["write_tokens"].nil?
        policy |= Configurable::ForkPrWorkflowsPolicy::WRITE_TOKENS if current_policy & Configurable::ForkPrWorkflowsPolicy::WRITE_TOKENS > 0
      else
        policy |= Configurable::ForkPrWorkflowsPolicy::WRITE_TOKENS if form_policy["write_tokens"]
      end

      if form_policy["send_secrets"].nil?
        policy |= Configurable::ForkPrWorkflowsPolicy::SEND_SECRETS if current_policy & Configurable::ForkPrWorkflowsPolicy::SEND_SECRETS > 0
      else
        policy |= Configurable::ForkPrWorkflowsPolicy::SEND_SECRETS if form_policy["send_secrets"]
      end

      entity.set_fork_pr_workflows_policy(policy: policy, actor: current_user)

      # handling approval settings separately
      current_approvals = entity.actions_private_fork_pr_approvals_policy

      if form_policy["require_approvals"].nil?
        approval_policy = current_approvals
      else
        approval_policy = if form_policy["require_approvals"]
          Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
        else
          Configurable::ActionsPrivateForkPrApprovals::NONE
        end
      end

      entity.set_actions_private_fork_pr_approvals_policy(
        policy: approval_policy,
        actor: current_user
      )
    else
      # Disable workflows
      entity.disable_fork_pr_workflows(actor: current_user)

      # Always reset approval policy when workflows are disabled
      entity.set_actions_private_fork_pr_approvals_policy(
        policy: Configurable::ActionsPrivateForkPrApprovals::NONE,
        actor: current_user
      )
    end
  end
end
