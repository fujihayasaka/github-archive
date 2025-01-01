# typed: true
# frozen_string_literal: true

# Parent controller for all other site admin controllers.
class StafftoolsController < ApplicationController
  include Stafftools::AccessControlHelper
  include AuditLogHelper
  include IRepositoryController

  # Stafftools actions for multi tenant should function in a similar way to dotcom.
  # Searching in stafftools for a user or organization should return all users,
  # regardless of which tenant they belong to.
  if GitHub.multi_tenant_enterprise?
    before_action :upgrade_or_revoke_user_staffroles_multitenant
    around_action :unscope_stafftools
  end

  before_action :push_failbot_metadata
  before_action :require_admin_frontend, except: :modal
  before_action :site_admin_only
  before_action :login_required
  before_action :sudo_filter
  before_action :increment_stats
  before_action :disable_onboarding_notice
  skip_before_action :cap_pagination
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:modal]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  unless GitHub.enterprise?
    before_action :ensure_stafftools_authorization
    before_action :prompt_for_hubber_access
  end

  layout "stafftools"
  javascript_bundle :stafftools
  stylesheet_bundle :stafftools

  helper_method :this_user

  def index
    render "stafftools/index"
  end

  def modal # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        if request.xhr?
          render "stafftools/modal", layout: false
        else
          redirect_to stafftools_url
        end
      end
    end
  end

  private

  # Find the current user from the route
  #
  # user - The login name of the user in question
  memoize def this_user
    login = if params[:user_id]
      params[:user_id]
    elsif params[:user].is_a?(String)
      # Sometimes (especially on #invite), it's a Hash
      params[:user]
    elsif params[:id]
      params[:id]
    end

    User.where(type: %w[User Organization]).find_by(login: login)
  end

  # Lookup the user, 404 out if we can't find it because it has been deleted or because it doesn't
  # exist at all.
  def ensure_user_exists
    return render_404 unless this_user.present?

    # 404 if feature flag enabled and this_user is an organization in the deleted state
    if current_user.feature_enabled?(:stafftools_hide_deleted_organization)
      render_404 if this_user.organization? && this_user.deleted?
    end
  end

  # Ensures that the current user is an EMU
  def ensure_enterprise_managed_user
    return render_404 unless this_user
    return render_404 unless this_user.user?
    return render_404 unless this_user.is_enterprise_managed?
  end

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  def prompt_for_hubber_access
    return unless this_user && this_user.employee?
    return if this_user == current_user
    if !current_user.hubber_access_reason_provided?(this_user)
      render "stafftools/users/locked_user"
    end
  end

  def set_default_nav_breadcrumb
    context_region_preset :stafftools
  end

  def disable_onboarding_notice
    @global_nav_onboarding_enabled = false
  end

  # Override to ensure business footer is not enabled for StafftoolsController and subclasses.
  def business_footer_enabled?
    false
  end
  helper_method :business_footer_enabled?

  def upgrade_or_revoke_user_staffroles_multitenant
    return unless current_user
    return unless GitHub::CurrentTenant.stafftools_tenant?

    Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(current_user)
  end

  def unscope_stafftools
    GitHub::CurrentTenant.unscope do
      yield
    end
  end

  def push_failbot_metadata
    Failbot.push(app: "github-stafftools", stafftools: true)
  end

  def ensure_account_is_user
    render_404 unless this_user.user?
  end

  def ensure_org_not_user
    render_404 unless this_user&.organization?
  end

  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    reponame = params[:repository] || params[:repository_id] || params[:id]
    if owner
      # An owner might have multiple repositories with the same name as we
      # include deleted repositories here.  Therefore, we prefer active
      # repositories over deleted ones (first sort criteria). If there are
      # multiple deleted repositories with the same name, then we prefer the
      # one that was most recently modified (second sort criteria).
      @current_repository = Repository.where(owner_id: owner.id, name: reponame).order(active: :desc, updated_at: :desc).first
    end
  end

  def repository_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repository_access ||= current_repository.access
  end

  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @owner ||= User.find_by_login(params[:user_id]) if params[:user_id]
  end

  # Lookup the repo, 404 out if we can't find it
  def ensure_repo_exists
    render_404 unless current_repository
  end

  def this_team
    team_id = params[:team_id] || params[:id]
    @this_team ||= this_user.teams.find_by_slug(team_id) if this_user
  end
  helper_method :this_team

  def ensure_team_exists
    render_404 unless this_team
  end

  def this_issue # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_issue ||= begin
      issue_num = params[:issue_id] || params[:pull_request_id] || params[:id]
      current_repository.issues.find_by_number(issue_num.to_i)
    end
  end
  helper_method :this_issue

  def this_repository_advisory # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_repository_advisory ||= begin
      advisory_num = params[:repository_advisory_id] || params[:id]
      current_repository.repository_advisories.find_by!(id: advisory_num.to_i)
    end
  end
  helper_method :this_repository_advisory

  def ensure_issue_exists
    return render_404 if this_issue.nil?
  end

  def this_discussion # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_discussion ||= begin
      discussion_num = params[:discussion_id] || params[:id]
      current_repository.discussions.find_by_number(discussion_num.to_i)
    end
  end
  helper_method :this_discussion

  def ensure_discussion_exists
    return render_404 if this_discussion.nil?
  end

  def fetch_audit_log_teaser(query)
    @query = query
    es_query = Audit::Driftwood::Query.new_stafftools_query(
      phrase: query,
      current_user: current_user,
      per_page: 5,
    )

    results = es_query.execute
    #Driftwood::Results does not have next_page.present?
    @more_results =
      if results.respond_to?(:has_next_page?)
        results.has_next_page?
      else
        results.next_page.present?
      end
    @logs = AuditLogEntry.new_from_array(results)
    {
      query: @query,
      more_results: @more_results,
      logs: @logs,
    }
  end

  # Increment stats so we can see what parts of stafftools are used most
  def increment_stats
    controller = params[:controller].gsub(/^stafftools\//, "").gsub("/", "_")
    method = request.try(:method).downcase
    action = params[:action]
    GitHub.dogstats.increment("request.stafftools", tags: ["controller:#{controller}", "method:#{method}", "action:#{action}"])
  end

  def instrument(key, payload = {})
    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(current_user)
    GitHub.instrument(key, payload.merge(auditing_actor))
  end

  # Verify Hubber has an appropriate stafftools role for this action.
  def ensure_stafftools_authorization
    stafftools_action = { controller: self.class.name, action: action_name }
    unless logged_in? && Stafftools::AccessControl.authorized?(current_user, stafftools_action)
      render_403_for_employees
    end
  end

  def display_management_console_link?
    GitHub.management_console_enabled?
  end
  helper_method :display_management_console_link?

  def ensure_user_not_org
    render_404 unless this_user&.user?
  end

  def redirect_back_with_anchor(anchor)
    redirect_to request.referrer + anchor
  end
end
