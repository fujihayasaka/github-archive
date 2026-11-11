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

    runner_groups = Actions::RunnerGroup.for_entity(this_user, include_runners: true, include_runner_scale_sets: true, include_hosted_runner_groups: false, is_ui_read: true)

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
      max_concurrent_macos_jobs_stafftools_limit = actions_plan_owner.max_concurrent_macos_jobs_stafftools_limit
    end

    # Fetch trust tier information
    tier_result = ::TrustTiers::Tier.for_billable_owner(this_user)
    trust_tier = tier_result.tier
    trust_tier_name = ::TrustTiers::Tier.tier_name(trust_tier)

    # Fetch concurrency limits from Launch service
    # Returns nil if no overrides are set (which is normal)
    concurrency_limits = fetch_concurrency_limits(this_user)

    # Check if organization belongs to an enterprise
    in_business = this_user.business.present?
    parent_business = this_user.business if in_business

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
        max_concurrent_macos_jobs_stafftools_limit: max_concurrent_macos_jobs_stafftools_limit,
        concurrency_limits: concurrency_limits,
        actions_general_settings: actions_org_general_settings(this_user),
        in_business: in_business,
        parent_business: parent_business,
        trust_tier: trust_tier,
        trust_tier_name: trust_tier_name
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

  def update_concurrency_limits # rubocop:todo GitHub/UseRestfulActions
    total_limit = params[:total_limit].to_i
    macos_limit = params[:macos_limit].to_i

    if total_limit < 0 || macos_limit < 0
      flash[:error] = "Limits cannot be negative"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    if total_limit > 0 && macos_limit > total_limit
      flash[:error] = "macOS limit cannot be greater than total limit"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    # Get plan-based limits for validation
    actions_plan_owner = ActionsPlanOwner.new(this_user)
    plan_max_concurrent_jobs = actions_plan_owner.max_concurrent_jobs_guess
    plan_max_concurrent_macos_jobs = actions_plan_owner.max_concurrent_macos_jobs_guess
    stafftools_max_macos = actions_plan_owner.max_concurrent_macos_jobs_stafftools_limit

    # Validate total limit is at most double the plan-based limit
    if total_limit > (plan_max_concurrent_jobs * 2)
      flash[:error] = "Total limit (#{total_limit}) cannot exceed double the plan-based limit (#{plan_max_concurrent_jobs * 2})"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    # Validate macOS limit is not increased beyond the stafftools-allowed limit for this plan
    if macos_limit > stafftools_max_macos
      flash[:error] = "macOS limit (#{macos_limit}) cannot exceed the stafftools limit (#{stafftools_max_macos})"
      redirect_to stafftools_org_actions_path(this_user)
      return
    end

    success = Launch::Twirp.concurrency_limit_overrides_client.update_concurrency_limit_overrides(
      owner: this_user,
      total_limit: total_limit,
      macos_limit: macos_limit
    )

    if success
      flash[:notice] = "Concurrency limits updated successfully: Total=#{total_limit}, macOS=#{macos_limit}"

      # Log audit event
      audit_payload = {
        org: this_user.display_login,
        org_id: this_user.id,
        total_limit: total_limit,
        macos_limit: macos_limit,
        plan_max_concurrent_jobs: plan_max_concurrent_jobs,
        plan_max_concurrent_macos_jobs: plan_max_concurrent_macos_jobs,
        from: "stafftools/actions#update_concurrency_limits"
      }
      GitHub.logger.info("About to instrument audit event", audit_payload)
      instrument("org.update_actions_concurrency_limits", audit_payload)
      GitHub.logger.info("Audit event instrumented successfully")

      GitHub.logger.info("Concurrency limits updated from stafftools",
        {
          "success" => true,
          "owner_id" => this_user.id,
          "owner_login" => this_user.login,
          "total_limit" => total_limit,
          "macos_limit" => macos_limit,
          "plan_max_concurrent_jobs" => plan_max_concurrent_jobs,
          "plan_max_concurrent_macos_jobs" => plan_max_concurrent_macos_jobs,
        }
      )
    else
      flash[:error] = "Failed to update concurrency limits"
      GitHub.logger.error("Failed to update concurrency limits from stafftools",
        {
          "success" => false,
          "owner_id" => this_user.id,
          "owner_login" => this_user.login,
        }
      )
    end

    redirect_to stafftools_org_actions_path(this_user)
  end

  private

  def fetch_concurrency_limits(owner)
    limits = Launch::Twirp.concurrency_limit_overrides_client.get_concurrency_limit_overrides(owner: owner)
    if limits.present? && (limits[:total].present? || limits[:macos].present?)
      {
        total: limits[:total],
        macos: limits[:macos],
        source: "launch_service"
      }
    else
      # No overrides set for this owner - this is a normal case
      nil
    end
  rescue => e
    GitHub.logger.error("Exception fetching concurrency limits from Launch service",
      {
        "owner_id" => owner.id,
        "owner_login" => owner.login,
        "exception" => e.message,
      }
    )
    nil
  end

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
