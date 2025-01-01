# typed: true
# frozen_string_literal: true

class BranchProtectionRulesController < AbstractRepositoryController
  include Platform::Mutations::Shared::ModifyBranchProtectionRule

  before_action :login_required
  before_action :writable_repository_required

  before_action :sudo_filter, only: %i(create update destroy)

  before_action :ensure_user_has_edit_branch_protection # Currently edit permission is required to even load the page
  before_action :ensure_policy_permits_updating_branch_protection, only: %i(new create update destroy)


  layout "repository"
  javascript_bundle :settings
  javascript_bundle :repositories

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::ActionsEnvironments,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::ActionsEnvironments,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:show, :new]

  def new
    protected_branch = ProtectedBranch.new(
      repository: current_repository,
      strict_required_status_checks_policy: false,
    )
    render "branch_protection_rules/new", locals: { protected_branch: protected_branch }
  end

  def create
    inputs = required_status_check_mutation_input.merge(
      pattern: params[:rule],
      requires_approving_reviews: params[:has_required_reviews].present?,
      required_approving_review_count: params[:required_approving_review_count].present? ? params[:required_approving_review_count].to_i : nil,
      restricts_review_dismissals: params[:required_reviews_enforce_dismissal].present?,
      requires_commit_signatures: params[:has_signature_requirement].present?,
      requires_linear_history: params[:block_merge_commits].present?,
      blocks_creations: params[:blocks_creations].present?,
      allows_force_pushes: params[:allows_force_pushes].present?,
      allows_deletions: params[:allows_deletions].present?,
      is_admin_enforced: params[:enforce_all_for_admins].present?,
      requires_status_checks: params[:has_required_statuses].present?,
      requires_strict_status_checks: params[:strict_required_status_checks_policy].present?,
      requires_code_owner_reviews: params[:require_code_owner_review].present?,
      dismisses_stale_reviews: params[:dismiss_stale_reviews_on_push].present?,
      restricts_pushes: params[:authorized_actors].present?,
      review_dismissal_actor_ids: review_dismissal_actor_ids,
      bypass_pull_request_actor_ids: bypass_pull_request_actor_global_ids,
      bypass_force_push_actor_ids: bypass_force_push_actor_global_ids,
      push_actor_ids: push_actor_ids,
      requires_deployments: params[:has_required_deployments].present?,
      required_deployment_environments: params[:deployment_environments],
      requires_merge_queue: params[:requires_merge_queue].present?,
      merge_queue_check_run_retries: params[:merge_queue_check_run_retries]&.to_i,
      merge_queue_merge_method: params[:merge_queue_merge_method]&.to_s&.downcase,
      merge_queue_min_entries_to_merge_wait_time: params[:merge_queue_min_entries_to_merge_wait_time]&.to_i,
      merge_queue_max_entries_to_merge: params[:merge_queue_max_entries_to_merge]&.to_i,
      merge_queue_min_entries_to_merge:  params[:merge_queue_min_entries_to_merge]&.to_i,
      merge_queue_max_entries_to_build:  params[:merge_queue_max_entries_to_build]&.to_i,
      merge_queue_check_response_timeout: params[:merge_queue_check_response_timeout]&.to_i,
      merge_queue_merging_strategy: params[:merge_queue_merging_strategy].present? ? "ALLGREEN" : "HEADGREEN",
      ignore_approvals_from_contributors: params[:ignore_approvals_from_contributors].present?,
      requires_conversation_resolution: params[:requires_conversation_resolution].present?,
      require_last_push_approval: params[:require_last_push_approval].present?,
      lock_branch: params[:lock_branch].present?,
      lock_allows_fetch_and_merge: params[:lock_allows_fetch_and_merge].present?,
    )
    protected_branch = current_repository.protected_branches.build(name: inputs[:pattern], creator: current_user)
    modify_branch_protection_rule(protected_branch, inputs, entry_point: :branch_protection_rules_controller_create)
    flash[:notice] = "Branch protection rule created."
    redirect_to edit_repository_branches_path
  rescue Platform::Errors::Execution => error
    flash[:error] = error.message
    redirect_to new_branch_protection_rule_path(enable_tip: params[:enable_tip], guidance_task: params[:guidance_task])
  end

  def show
    protected_branch = current_repository.protected_branches.find(params[:id])

    render "branch_protection_rules/show", locals: { protected_branch: protected_branch }
  rescue ActiveRecord::RecordNotFound => error
    render_404
  end

  def update
    protected_branch = current_repository.protected_branches.find(params[:id])

    inputs = required_status_check_mutation_input.merge(
      branch_protection_rule_id: protected_branch.global_relay_id,
      pattern: params[:rule],
      requires_approving_reviews: params[:has_required_reviews].present?,
      required_approving_review_count: params[:required_approving_review_count].present? ? params[:required_approving_review_count].to_i : nil,
      restricts_review_dismissals: params[:required_reviews_enforce_dismissal].present?,
      requires_commit_signatures: params[:has_signature_requirement].present?,
      requires_linear_history: params[:block_merge_commits].present?,
      blocks_creations: params[:blocks_creations].present?,
      allows_force_pushes: params[:allows_force_pushes].present?,
      allows_deletions: params[:allows_deletions].present?,
      is_admin_enforced: params[:enforce_all_for_admins].present?,
      requires_status_checks: params[:has_required_statuses].present?,
      requires_strict_status_checks: params[:strict_required_status_checks_policy].present?,
      requires_code_owner_reviews: params[:require_code_owner_review].present?,
      dismisses_stale_reviews: params[:dismiss_stale_reviews_on_push].present?,
      restricts_pushes: params[:authorized_actors].present?,
      review_dismissal_actor_ids: review_dismissal_actor_ids,
      bypass_pull_request_actor_ids: bypass_pull_request_actor_global_ids,
      bypass_force_push_actor_ids: bypass_force_push_actor_global_ids,
      push_actor_ids: push_actor_ids,
      requires_deployments: params[:has_required_deployments].present?,
      required_deployment_environments: params[:deployment_environments],
      requires_merge_queue: params[:requires_merge_queue].present?,
      merge_queue_check_run_retries: params[:merge_queue_check_run_retries]&.to_i,
      merge_queue_merge_method: params[:merge_queue_merge_method]&.to_s&.downcase,
      merge_queue_min_entries_to_merge_wait_time: params[:merge_queue_min_entries_to_merge_wait_time]&.to_i,
      merge_queue_max_entries_to_merge: params[:merge_queue_max_entries_to_merge]&.to_i,
      merge_queue_min_entries_to_merge:  params[:merge_queue_min_entries_to_merge]&.to_i,
      merge_queue_max_entries_to_build:  params[:merge_queue_max_entries_to_build]&.to_i,
      merge_queue_check_response_timeout: params[:merge_queue_check_response_timeout]&.to_i,
      merge_queue_merging_strategy: params[:merge_queue_merging_strategy].present? ? "ALLGREEN" : "HEADGREEN",
      ignore_approvals_from_contributors: params[:ignore_approvals_from_contributors].present?,
      requires_conversation_resolution: params[:requires_conversation_resolution].present?,
      require_last_push_approval: params[:require_last_push_approval].present?,
      lock_branch: params[:lock_branch].present?,
      lock_allows_fetch_and_merge: params[:lock_allows_fetch_and_merge].present?,
    )

    protected_branch.name = inputs[:pattern] unless inputs[:pattern].nil?
    modify_branch_protection_rule(protected_branch, inputs, entry_point: :branch_protection_rules_controller_update)
    flash[:notice] = "Branch protection rule settings saved."
    redirect_to edit_repository_branches_path
  rescue ActiveRecord::RecordNotFound => error
    flash[:error] = "Branch protection rule does not exist."
    redirect_to edit_repository_branches_path
  rescue ActiveRecord::ActiveRecordError => error
    Failbot.report(error, {
      "gh.repo.id": current_repository.id
    })
    flash[:error] = "Unable to save branch protection rule."
    redirect_to branch_protection_rule_path(id: protected_branch.id)
  rescue Platform::Errors::Execution => error
    flash[:error] = error.message
    GitHub.logger.error({
      exception: error,
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": current_repository.id,
      "gh.branch_protection_rule.id": protected_branch.id,
    })
    redirect_to branch_protection_rule_path(id: protected_branch.id)
  end

  def destroy
    begin
      protected_branch = current_repository.protected_branches.find(params[:id])
      protected_branch.destroy_with_args!(entry_point: :branch_protection_rules_controller_destroy)
      flash[:notice] = "Branch protection rule was successfully deleted."
    rescue ActiveRecord::RecordNotFound => error
      flash[:error] = "Branch protection rule was already deleted."
    rescue ActiveRecord::ActiveRecordError => error
      Failbot.report(error, {
        "gh.repo.id": current_repository.id
      })
      flash[:error] = "Unable to delete branch protection rule."
    ensure
      redirect_to edit_repository_branches_path
    end
  end

  def integration_suggestions # rubocop:disable GitHub/UseRestfulActions
    inputs = params.require(:items).permit!.to_h

    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      protected_branch_id = inputs.values.first["protected_branch_id"]
      protected_branch = if protected_branch_id.present?
        current_repository.protected_branches.find(protected_branch_id.to_i)
      else
        ProtectedBranch.new(repository: current_repository)
      end

      integration_by_context = inputs.map do |(_key, item)|
        [item["context"], item["integration_id"]]
      end.to_h

      possible_options = protected_branch.possible_required_status_contexts_and_integrations

      inputs.each_with_object({}) do |(key, item), contents|
        possible_integrations = possible_options[item["context"]]
        selected_integration = if possible_integrations.present? && item["integration_id"].present?
          possible_integrations.find { |integration| integration.id == item["integration_id"].to_i }
        else
          nil
        end

        contents[key] = render_integration_suggestions(item["context"], selected_integration, possible_integrations)
      end
    end

    respond_to do |format|
      format.json do
        render json: keyed_contents
      end
    end
  end

  private

  def review_dismissal_actor_ids
    actors = User.where(id: Array(params[:dismiss_user_ids]&.filter_map(&:presence))) +
             Team.where(id: Array(params[:dismiss_team_ids]&.filter_map(&:presence))) +
             Integration.where(id: Array(params[:dismiss_integration_ids]&.filter_map(&:presence)))

    actors.map(&:global_relay_id)
  end

  def bypass_pull_request_actor_global_ids
    user_ids = Array.wrap(params[:bypass_pr_user_ids])
    team_ids = Array.wrap(params[:bypass_pr_team_ids])
    integration_ids = Array.wrap(params[:bypass_pr_integration_ids])
    result = []
    result.concat(User.where(id: user_ids).to_ary) if user_ids.any?
    result.concat(Team.where(id: team_ids).to_ary) if team_ids.any?
    result.concat(Integration.where(id: integration_ids).to_ary) if integration_ids.any?
    result.map(&:global_relay_id)
  end

  def bypass_force_push_actor_global_ids
    user_ids = Array.wrap(params[:bypass_fp_user_ids])
    team_ids = Array.wrap(params[:bypass_fp_team_ids])
    integration_ids = Array.wrap(params[:bypass_fp_integration_ids])
    result = []
    result.concat(User.where(id: user_ids).to_ary) if user_ids.any?
    result.concat(Team.where(id: team_ids).to_ary) if team_ids.any?
    result.concat(Integration.where(id: integration_ids).to_ary) if integration_ids.any?
    result.map(&:global_relay_id)
  end

  def push_actor_ids
    actors = User.where(id: Array(params[:push_user_ids]&.filter_map(&:presence))) +
             Team.where(id: Array(params[:push_team_ids]&.filter_map(&:presence))) +
             Integration.where(id: Array(params[:push_integration_ids]&.filter_map(&:presence)))
    actors.map(&:global_relay_id)
  end

  # This is checking that the user has permissions to edit branch protections. Currently, you need this permission to
  # even load the page.
  def ensure_user_has_edit_branch_protection
    unless current_repository.async_can_edit_repo_protections?(current_user).sync
      render plain: "Not found.", status: 404
    end
  end

  # Enterprise- or org-level policies can prohibit even repo admins from editing protections
  def ensure_policy_permits_updating_branch_protection
    unless current_repository.can_update_protected_branches?(current_user)
      render plain: "Protected branch updating is disabled on this repository.", status: 403
    end
  end

  def required_status_check_mutation_input
    if params[:integration_ids]
      status_checks = params[:integration_ids].to_unsafe_hash.map do |context, integration_id|
        { status_context: Base64.urlsafe_decode64(context).force_encoding("utf-8").strip, app_id: integration_id }
      end
      { required_status_checks: status_checks }
    else
      { required_status_check_contexts: params[:contexts]&.filter_map(&:presence) || [] }
    end
  end

  def modify_branch_protection_rule(protected_branch, inputs, entry_point:)
    context = platform_context
    context[:permission] = Platform::Authorization::Permission.new(
      viewer: current_user,
      origin: Platform::ORIGIN_INTERNAL
    )
    update_branch_protection_rule(protected_branch, inputs, context, entry_point: entry_point)
  end

  def render_integration_suggestions(context, selected_integration, integrations)
    render_to_string(
      partial: "branch_required_status_contexts/integration_select",
      formats: [:html],
      locals: {
        context:,
        selected_integration:,
        integrations:,
      }
    )
  end
end
