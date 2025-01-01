# typed: true
# frozen_string_literal: true

class Stafftools::ActionsController < StafftoolsController
  include Secrets::Helper
  include Variables::Helper
  include Actions::LargerRunnersHelper

  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show_org_actions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_org_actions],
    optional: true

  def show_org_actions # rubocop:todo GitHub/UseRestfulActions
    secrets = secrets_for(this_user, app: actions_integration).map do |secret|
      {
        name: secret.name,
        visibility_description: visibility_description_for_secret(secret, can_use_secrets_for_private_repos?, this_user.business.present?),
        created_at: Secrets.secret_created_at(secret),
        updated_at: Secrets.secret_updated_at(secret)
      }
    end
    variables = variables_for(this_user, app: actions_integration).map do |variable|
      {
        name: variable.name,
        value: variable.value,
        visibility_description: visibility_description_for_variable(variable, can_use_variables_for_private_repos?, this_user.business.present?),
        created_at: Variables.variable_created_at(variable),
        updated_at: Variables.variable_updated_at(variable)
      }
    end

    runner_groups = Actions::RunnerGroup.for_entity(this_user, include_runners: true, include_runner_scale_sets: true, include_hosted_runner_groups: false)

    if this_user.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: this_user)
      larger_runners.each do |larger_runner|
        group = runner_groups.detect { |runner_group| runner_group.id == larger_runner.runner_group_id }
        if group.present?
          group.runners.append(larger_runner)
        end
      end
    end

    runners = runner_groups.flat_map(&:runners)

    if GitHub.billing_enabled?
      actions_plan_owner = ActionsPlanOwner.new(this_user)
      plan_name = actions_plan_owner.plan_name.titleize
      max_concurrent_jobs = actions_plan_owner.max_concurrent_jobs_guess
      max_concurrent_macos_jobs = actions_plan_owner.max_concurrent_macos_jobs_guess
    end

    render "stafftools/organizations/actions",
      layout: "layouts/stafftools/organization/content",
      locals: {
        secrets: secrets,
        variables: variables,
        runner_groups: runner_groups,
        hosted_runner_group: nil,
        runners: runners,
        plan_name: plan_name,
        max_concurrent_jobs: max_concurrent_jobs,
        max_concurrent_macos_jobs: max_concurrent_macos_jobs,
        actions_general_settings: actions_org_general_settings(this_user),
      }
  end

  def show_user_actions # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/actions",
      layout: "layouts/stafftools/user/content"
  end

  def restore_billing_owner # rubocop:todo GitHub/UseRestfulActions
    if this_user.spammy?
      flash[:error] = "Cannot restore spammy user"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end
    owner = this_user.business.present? ? ActionsPlanOwner.new(this_user.business) : ActionsPlanOwner.new(this_user)
    result = Launch::Twirp.deployer_client.report_admin_event_for_billing_owner(owner.database_id, owner.id, owner.name, "BillingOwnerRestored")
    if result.call_succeeded?
      flash[:notice] = "Actions billing owner restore requested."
    else
      flash[:error] = "Actions billing owner restore failed."
    end

    GitHub.dogstats.increment("stafftools.actions.restore_billing_owner", tags: ["success:#{result.call_succeeded?}"])
    GitHub.logger.info("Actions billing owner restore requested from stafftools",
      {
        "success" => result.call_succeeded?,
        "owner_id" => owner.id,
        "owner_name" => owner.name,
      }
    )

    if this_user.organization?
      redirect_to stafftools_org_actions_path(this_user)
    else
      redirect_to stafftools_user_actions_path(this_user)
    end
  end

  def onboard_larger_runners # rubocop:todo GitHub/UseRestfulActions
    unless this_user.organization?
      flash[:error] = "Cannot onboard user to larger runners"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    org = this_user

    unless org.is_eligible_to_onboard_larger_runners?
      flash[:error] = "Organization is not eligible to onboard to larger runners"
      redirect_to stafftools_org_actions_path(org)
      return
    end

    # Setup tenant in Actions
    result = Launch::Twirp.deployer_client.setup_tenant(org)
    unless result.call_succeeded?
      flash[:error] = "Failed to set up tenant for Organization"
      redirect_to stafftools_org_actions_path(org)
      return
    end

    # Onboard account on dotcom side
    org.onboard_larger_runners(actor: User.staff_user)

    # Make any call to Runner service to fault-in account
    Actions::LargerRunner.larger_runners_for(entity: org)

    flash[:notice] = "Organization has been successfully onboarded to larger runners"
    redirect_to stafftools_org_actions_path(org)
  end

  def larger_runners_manage_beta_features # rubocop:todo GitHub/UseRestfulActions
    unless this_user.organization?
      flash[:error] = "Cannot manage larger runners features for user"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    org = this_user

    unless org.is_larger_runners_onboarded? && org.can_use_larger_runners?
      flash[:error] = "Organization is not onboarded to larger runners"
      redirect_to stafftools_org_actions_path(org)
      return
    end

    if params[:feature_name].present?
      feature_name = params[:feature_name]
    else
      flash[:error] = "Feature name is required"
      redirect_to stafftools_org_actions_path(org)
      return
    end

    if params[:feature_new_state] == "true"
      feature_new_state = true
    elsif params[:feature_new_state] == "false"
      feature_new_state = false
    else
      flash[:error] = "Feature new state is required"
      redirect_to stafftools_org_actions_path(org)
      return
    end

    result = Launch::Twirp::larger_runners_client.set_beta_feature(org, feature_name: feature_name, enabled: feature_new_state)
    unless result.call_succeeded?
      flash[:error] = "Failed to switch feature '#{feature_name}' to #{feature_new_state} for organization."
      redirect_to stafftools_org_actions_path(org)
      return
    end

    flash[:notice] = "Feature #{feature_name} was #{feature_new_state ? "enabled" : "disabled" } for organization successfully."
    redirect_to stafftools_org_actions_path(org)
  end

  def opt_out_of_immutable_actions_for_self_hosted_runners # rubocop:todo GitHub/UseRestfulActions
    new_opt_out_state = params[:opt_out_new_state]
    if !new_opt_out_state.present?
      flash[:error] = "opt_out_new_state new state is required in request"
    else
      opt_out_record = ImmutableActionsOptOut.where(workflow_repo_owner: this_user).first
      if new_opt_out_state == "true"
        if opt_out_record.blank?
          ImmutableActionsOptOut.create!(workflow_repo_owner: this_user, last_reported_at: Time.now)
          flash[:notice] = "Immutable actions opted out for self-hosted and larger runners for #{this_user.display_login}"
        else
          flash[:error] = "Opt out record for #{this_user.display_login} already exists"
        end
      else
        if opt_out_record.present?
          opt_out_record.delete
          flash[:notice] = "Immutable actions not opted out for self-hosted and larger runners for #{this_user.display_login}"
        else
          flash[:error] = "Unable to find existing opt-out record for #{this_user.display_login}"
        end
      end
    end

    if this_user.organization?
      redirect_to stafftools_org_actions_path(this_user)
    else
      redirect_to stafftools_user_actions_path(this_user)
    end
  end

  private

  def actions_org_general_settings(org)

    if org.allows_all_actions?
      allowed_actions = "ALL"
    elsif org.allows_specified_actions?
      allowed_actions = "SELECTED"
    else
      allowed_actions = "LOCAL_ONLY"
    end

    org_oidc_sub_claim = OrganizationOIDCSubClaimTemplate.get_template_for_org(org.id)

    settings = Hash.new
    settings["what_repositories_can_use_actions"] = org.actions_access
    settings["what_actions_can_be_used"] = org.actions_disabled? ? "none" : allowed_actions
    settings["artifacts_and_logs_retention_period"] = org.actions_retention_limit
    settings["what_collaborators_require_approval_to_run_workflows"] = org.actions_fork_pr_approvals_policy
    settings["workflow_default_permissions"] = org.actions_default_workflow_permissions_read_only? ? "read" : "read and write"
    settings["workflow_pr_approval_counts"] = org.actions_workflow_permission_can_approve_pr?
    settings["org_oidc_sub_claim"] = org_oidc_sub_claim.present? ? org_oidc_sub_claim.template : "No custom template set"
    settings
  end

  def actions_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= GitHub.launch_github_app
  end

  def can_use_secrets_for_private_repos?
    this_user.plan.supports?(:private_secrets_and_variables)
  end

  def can_use_variables_for_private_repos?
    this_user.plan.supports?(:private_secrets_and_variables)
  end
end
