# typed: true
# frozen_string_literal: true

class Businesses::Actions::PoliciesController < BusinessesController
  include ::Actions::PolicyHelper
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :dotcom_required, only: [:update_fork_pr_approvals_policy, :update_custom_images_policy, :bulk_update_custom_images_policy_for_orgs, :update_custom_images_retention_policy]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_valid_self_hosted_runners_values, only: [:update_repo_self_hosted_runners]
  before_action :parse_json_params, only: [:update_custom_images_policy, :bulk_update_custom_images_policy_for_orgs, :update_custom_images_retention_policy]

  allow_verified_fetch only: [:update_custom_images_policy, :bulk_update_custom_images_policy_for_orgs, :update_custom_images_retention_policy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:bulk]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:bulk],
    optional: true

  def update_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:fork_pr_workflows_policy] || {}
    set_fork_pr_workflows_policy(this_business, form_policy)
  end

  def update_public_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:public_fork_pr_workflows_policy] || {}
    set_public_fork_pr_workflows_policy(this_business, form_policy)
  end

  def update_fork_pr_approvals_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:actions_fork_pr_approvals] || {}
    set_actions_fork_pr_approvals_policy(this_business, form_policy)
  end

  def update_default_workflow_permissions # rubocop:todo GitHub/UseRestfulActions
    # Default workflow permission and PR approval allowed flags are stored together
    wf_default = params[:actions_default_workflow_permissions] || {}
    wf_pr_approve = params[:actions_workflow_permission_can_approve_pr] || {}
    set_default_and_approval_workflow_permissions(this_business, wf_default, wf_pr_approve)
  end

  def update_repo_self_hosted_runners # rubocop:todo GitHub/UseRestfulActions
    policy = params[:repo_self_hosted_runners_is_disabled] || {}
    case policy
    when "1"
      this_business.disable_repo_self_hosted_runners(actor: current_user)
    when "0", {}
      this_business.enable_repo_self_hosted_runners(actor: current_user)
    end

    emus_policy = params[:repo_self_hosted_runners_is_disabled_for_emus] || {}
    case emus_policy
    when "1"
      this_business.disable_repo_self_hosted_runners_for_emus(actor: current_user)
    when "0", {}
      this_business.enable_repo_self_hosted_runners_for_emus(actor: current_user)
    end

    if this_business.errors.any?
      flash[:error] = "Sorry, there was an issue updating your settings."
      return redirect_to settings_actions_enterprise_path(this_business)
    end

    flash[:notice] = "Repo-level self-hosted runners settings changed."
    redirect_to settings_actions_enterprise_path(this_business)
  end

  def bulk # rubocop:todo GitHub/UseRestfulActions
    orgs = this_business.organizations.where(id: params[:organization_ids])

    respond_to do |format|
      format.html do
        render(Businesses::Actions::OrgBulkEnableComponent.new(
          business: this_business,
          organizations: orgs
        ), layout: false)
      end
    end
  end

  def bulk_update # rubocop:todo GitHub/UseRestfulActions
    organizations = this_business.organizations.where(id: params[:organization_ids])
    enablement = params[:enablement]

    case enablement
    when "enabled"
      organizations.each { |org| org.allow_actions(actor: current_user) }
    when "disabled"
      organizations.each { |org| org.disallow_actions(actor: current_user) }
    end

    view = Businesses::Settings::ActionsPoliciesView.new(
      business: this_business,
      query: params["q"],
      current_page: current_page
    )

    render partial: "businesses/settings/actions/orgs", locals: { view: view }
  end

  def enable_org # rubocop:todo GitHub/UseRestfulActions
    organization_name = params[:organization]
    enablement = params[:enablement]

    organization = this_business.organizations.find_by_login(organization_name)

    return unless organization.present?

    case enablement
    when "enabled"
      organization.allow_actions(actor: current_user)
    when "disabled"
      organization.disallow_actions(actor: current_user)
    end

    render(
      Businesses::Actions::OrgRowComponent.new(
        business: this_business,
        organization: organization,
        enabled: organization.actions_allowed_by_owner?
      ),
      layout: false
    )
  end

  def update_custom_images_policy # rubocop:todo GitHub/UseRestfulActions
    policy = params[:accessPolicy] || ""
    if Actions::CustomImagesPolicyUpdater.is_valid_option?(policy)
      Actions::CustomImagesPolicyUpdater.perform(entity: this_business, policy: policy, actor: current_user)
      render(json: {}, status: :created)
    else
      render(json: {}, status: :unprocessable_entity)
    end
  end

  def bulk_update_custom_images_policy_for_orgs # rubocop:todo GitHub/UseRestfulActions
    # Only the orgs that are changed are sent from the UI
    organizations = this_business.organizations.where(id: params[:disabledOrgIds])
    organizations.each { |org| org.disallow_custom_images(actor: current_user) }

    organizations = this_business.organizations.where(id: params[:enabledOrgIds])
    organizations.each { |org| org.allow_custom_images(actor: current_user) }

    render(json: {}, status: :created)
  end

  def update_custom_images_retention_policy # rubocop:todo GitHub/UseRestfulActions
    image_versions_per_image_limit = params[:imageVersionsPerImageLimit].to_i
    image_versions_max_age_limit = params[:imageVersionsMaxAgeLimit].to_i
    image_versions_unused_age_limit = params[:imageVersionsUnusedAgeLimit].to_i

    if Actions::CustomImagesRetentionPolicyUpdater.valid_inputs?(
      entity: this_business,
      image_versions_per_image_limit: image_versions_per_image_limit,
      image_versions_max_age_limit: image_versions_max_age_limit,
      image_versions_unused_age_limit: image_versions_unused_age_limit
    )
      Actions::CustomImagesRetentionPolicyUpdater.perform(
      entity: this_business,
      image_versions_per_image_limit: image_versions_per_image_limit,
      image_versions_max_age_limit: image_versions_max_age_limit,
      image_versions_unused_age_limit: image_versions_unused_age_limit,
      actor: current_user
      )
      render json: { message: "Custom image retention settings updated." }, status: :ok
    else
      render json: { error: "Error saving your changes: Update failed." }, status: :unprocessable_entity
    end
  end

  def update_actions_access # rubocop:todo GitHub/UseRestfulActions
    if Actions::PolicyUpdater::VALID_OPTIONS.include? params[:policy]
      Actions::PolicyUpdater.perform(entity: this_business, policy: params[:policy], actor: current_user)
    else
      flash[:error] = "Sorry, there was an issue updating your settings."
    end

    redirect_to settings_actions_enterprise_path
  end

  def update_allowed_actions # rubocop:todo GitHub/UseRestfulActions
    policy = params[:allowedactions].to_s

    if Actions::Policy::AllowedActionsForm::VALID_OPTIONS.include? policy
      if policy == Actions::Policy::AllowedActionsForm::SPECIFIED_ACTIONS
        # If both were not passed, just set one of them for now.
        params["firstparty"] = true unless %w(firstparty marketplace patterns).any? { |k| params.key? k }
        this_business.enable_specified_actions_only(
            github_owned: params["firstparty"] || false,
            verified: params["marketplace"] || false,
            sha_pinning: params["sha_pinning"] || false,
            actor: current_user,
          )

        if params[:patterns]
          patterns = params[:patterns].split(/,\s*/).map(&:strip)
          allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(this_business, patterns: patterns, actor: current_user)
        end
      else
        Actions::AllowedTypesUpdater.perform(
          entity: this_business,
          policy: policy,
          sha_pinning: params[:sha_pinning] || false,
          actor: current_user
        )
      end

      if allowlist && allowlist.errors.any?
        flash[:error] = allowlist.errors.full_messages.to_sentence
      else
        flash[:notice] = "Actions policy updated."
      end
    else
      flash[:error] = "Sorry, there was an issue updating your settings."
    end

    redirect_to settings_actions_enterprise_path
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_valid_self_hosted_runners_values
    policy = params[:repo_self_hosted_runners_is_disabled] || {}
    emus = params[:repo_self_hosted_runners_is_disabled_for_emus] || {}
    valid = ["0", "1", {}]
    unless valid.include?(policy) && valid.include?(emus)
      flash[:error] = "Sorry, there was an issue updating your settings."
      redirect_to settings_actions_enterprise_path(this_business)
    end
  end
end
