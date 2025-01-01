# typed: true
# frozen_string_literal: true


# Internal: A base class for orgs controllers. This class provides a bunch of
# standard filter methods, plus a `this_organization` accessor.
#
# Beyond making general filters available, this controller requires a logged-in
# user and a valid `this_organization` by default.
class Orgs::Controller < ApplicationController
  extend T::Sig
  include OrganizationsHelper
  include OrganizationsControllerMethods

  preload_features [:two_factor_cap_enforcement]

  # Gotta have an active org to do org stuff. Override per-controller
  # where we need to handle soft and stuck hard deleted orgs.
  before_action :this_organization_required
  before_action :require_one_org_specified_in_params
  before_action :ensure_visible_to_current_user
  after_action :customer_category_instrumentation

  javascript_bundle :organizations
  stylesheet_bundle :orgs
  stylesheet_bundle :suggestions

  # Public: Get a Copilot::Organization for the organization currently being viewed.
  #
  # This method is public so that views can access it.
  #
  # Returns a Copilot::Organization when the URL-referenced organization is valid and the viewer is authenticated.
  # Returns nil otherwise.
  sig { returns T.nilable(Copilot::Organization) }
  memoize def current_copilot_organization
    org = current_organization
    Copilot::Organization.new(org) if org
  end

  protected

  ################################
  # Organization helpers/filters #
  ################################

  # Internal: Gets the organization we're operating inside based on an
  # `:org` param.
  #
  # Returns an Organization or nil if the org isn't found.
  def this_organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_organization if defined? @this_organization
    @this_organization = Organization.find_by_login(org_login_param)
  end
  helper_method :this_organization

  def require_one_org_specified_in_params
    # Make sure the viewer isn't trying to get around an access check; see
    # https://github.com/github/sponsors/issues/3846, https://github.com/github/code-scanning/issues/6167,
    # https://github.com/github/gitcoin/issues/8790
    org = params[:org]
    organization_id = params[:organization_id]
    render_404 if org.present? && organization_id.present? && org.downcase != organization_id.downcase
  end

  # Safe because of :this_organization_required
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_organization
  end

  def ensure_current_organization
    render_404 unless current_organization
  end

  def ensure_current_organization_for_billing
    render_404 unless current_organization_for_member_or_billing
  end

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  def billing_access_required
    render_404 unless org_billing_manageable?
  end

  # Internal: This before_action renders a standard 404 page if
  # `this_organization` is nil or has been soft deleted or
  # hard deleted and the clean-up got stuck
  #
  # Returns nothing.
  def this_organization_required
    render_404 if this_organization.nil? || this_organization.deleted?
  end

  # Internal:  This before_action renders a standard 404 page unless
  # the user can convert org members to outside collaborators
  def ensure_can_convert_to_outside_collaborators
    return if this_organization.allow_conversion_to_outside_collaborator?(actor: current_user)

    respond_to do |format|
      format.json { head 404 }
      format.html { render_404 }
    end
  end

  memoize def viewer_is_member_of_this_org?
    this_organization.direct_or_team_member?(current_user)
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of reading `this_organization`.
  #
  # Returns nothing.
  def organization_read_required
    if this_organization.nil? || !viewer_is_member_of_this_org?
      render_404
    end
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of reading `this_organization` or is an outside
  # collaborator on `this_organization`.
  #
  # Returns nothing.
  def organization_read_or_outside_collaborator_required
    if this_organization.nil? ||
        !viewer_is_member_of_this_org? &&
        !organization_outside_collaborators?
      render_404
    end
  end

  def organization_outside_collaborators?
    logged_in? && this_organization.user_is_outside_collaborator?(current_user.id)
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` has a role/FGP that grants them access to the organization
  # settings page
  #
  # Returns nothing
  def organization_setting_fgp_required
    return if this_organization && logged_in? && this_organization.can_view_organization_settings?(current_user)
    render_404
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of administering `this_organization`.
  #
  # Returns nothing.
  def organization_admin_required
    if this_organization.nil? || !this_organization.adminable_by?(current_user)
      render_404
    end
  end

  def organization_or_business_admin_required
    return render_404 if this_organization.nil?

    if current_user.is_enterprise_managed?
      return render_404 unless current_user.enterprise_managed_business.owner?(current_user) || this_organization.adminable_by?(current_user)

      # An EMU owner can add themself as the owner of the organization
      # An Organization admin can add any user as a member with admin or member role
      render_404 unless this_organization.adminable_by?(current_user) || params[:invitee_id] == current_user.id.to_s && params[:role] == "admin"
    else
      render_404 unless this_organization.adminable_by?(current_user)
    end
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of administering `this_organization`
  # or capable of administering `params[:repository]` and `params[:repository]` is owned by `this_organization`.
  #
  # Returns nothing
  def organization_admin_or_organization_repo_admin_required
    return render_404 if this_organization.nil?

    if !this_organization.adminable_by?(current_user)
      repo = this_organization.repositories.find_by_name(params[:repository])
      render_404 unless repo && repo.adminable_by?(current_user)
    end
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of administering `this_organization`.
  #
  # Returns nothing.
  def manage_security_products_permission_required
    return if this_organization && SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?
    render_404
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of reading the audit logs for `this_organization`.
  def read_org_audit_logs_permission_required
    return if this_organization && logged_in? && this_organization.can_read_org_audit_logs?(current_user)
    render_404
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of managing OAuth App policies for `this_organization`.
  def manage_org_oauth_policy_permission_required
    return if this_organization && logged_in? && this_organization.can_manage_org_oauth_app_policy?(current_user)
    render_404
  end

  # Internal: This before_action renders a 404 if the organization is marked
  # as spammy (unless the user who created it is the viewer)
  def ensure_visible_to_current_user
    if this_organization.present? && this_organization.hide_from_user?(current_user)
      render_404
    end
  end

  def invite_rate_limited_organization
    this_organization
  end

  ########################
  # Team helpers/filters #
  ########################

  # Internal: Gets the team we're operating inside based on a `:team_slug`
  # param.
  #
  # Returns a Team or nil if the team isn't found.
  def this_team # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_team if defined? @this_team

    slug = params[:team_slug]
    return if slug.blank?

    @this_team = this_organization.
      find_team_by_slug(slug, visible_to: current_user)
  end
  helper_method :this_team

  # Internal: This before_action renders a standard 404 page if `this_team` is
  # nil.
  #
  # Returns nothing.
  def this_team_required
    render_404 if this_team.nil?
  end

  def set_team_context_crumb
    return unless header_redesign_enabled?
    return if this_team.nil?
    set_nav_breadcrumb ContextRegion::TeamCrumb.new(this_team, current_user: current_user)
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of administering `this_team`.
  def admin_on_team_required
    if this_team.nil? || !this_team.adminable_by?(current_user)
      render_404
    end
  end

  # Internal: This before_action renders a 404 unless current_user can create
  # teams on the organization
  def organization_team_creation_required
    render_404 unless this_organization.can_create_team?(current_user)
  end

  def initialize_hydro_context
    super

    if hydro_context[:enabled] && this_organization
      hydro_context.merge!({
        current_org: this_organization.name,
        current_org_id: this_organization.id,
      })
    end
  end

  ############################
  # Insights helpers/filters #
  ############################

  # Internal: This before_action renders a 404 unless a user has secrets fine grained permission or is an org admin
  def organization_admin_or_actions_secrets_fine_grained_permission
    if params[:app_name] == Secrets::AppsHelper::ACTIONS_APP_NAME
      if this_organization.nil? || !this_organization.can_write_organization_actions_secrets?(current_user)
        render_404
      end
    else
      organization_admin_required
    end
  end

  # Internal: This before_action renders a 404 unless a user has secrets fine grained permission or is an org admin
  def organization_admin_or_actions_variables_fine_grained_permission
    if params[:app_name] == Variables::AppsHelper::ACTIONS_APP_NAME
      if this_organization.nil? || !this_organization.can_write_organization_actions_variables?(current_user)
        render_404
      end
    else
      organization_admin_required
    end
  end

  # Internal: This before_action renders a 404 unless insights is enabled for this_org and
  # current_user can access the organization's insights
  def organization_insights_required
    render_404 unless this_organization.insights_enabled? && this_organization.member?(current_user)
  end

  # Internal: This before_action renders a 404 unless dependency insights is enabled for current_user
  def organization_dependency_insights_required
    render_404 unless this_organization.dependency_insights_enabled_for?(current_user)
  end

  # Internal: This before_action renders a 404 unless a user is an admin or has the runners and runner groups FGP
  def ensure_user_has_runners_and_runner_groups_access
    return render_404 if this_organization.nil?
    render_404 unless this_organization.can_write_organization_runners_and_runner_groups?(current_user)
  end

  # Internal: This before_action renders a 404 unless a user is an admin or has the actions policies FGP
  def ensure_user_has_organization_actions_settings_access
    return render_404 if this_organization.nil?
    render_404 unless this_organization.can_write_organization_actions_settings?(current_user)
  end

  def pending_collaborators_invitations_scope
    invitations_scope = this_organization
      .repository_invitations
      .excluding_expired
      .preload(:repository, :invitee)

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].strip.downcase) if params[:query]

    if query.present?
      like_login_ids = User.where(id: invitations_scope.pluck(:invitee_id)).like_login_or_profile_name(query).pluck(:id)
      like_email_ids = invitations_scope.where.not(email: nil).where(["email LIKE :query", { query: "%#{query}%" }]).pluck(:id)
      invitations_scope = invitations_scope.where(invitee_id: like_login_ids).or(invitations_scope.where(id: like_email_ids))
    end

    invitations_scope
  end

  memoize def person
    User.find_by(login: params[:person_login])
  end

  def person_required
    if person.nil?
      flash["error"] = "This action cannot be performed because the user could not be found."
      redirect_to org_people_path(this_organization)
    end
  end

  def sso_enabled_required
    if GitHub.enterprise?
      render_404 unless GitHub.auth.saml?
    else
      # the saml_sso_present? will also check for OIDC provider
      render_404 unless this_organization.saml_sso_present?
    end
  end

  def sso_owner_required
    if this_organization.business&.external_provider_enabled?
      render_404 unless this_organization.business.adminable_by?(current_user)
    end
  end
end
