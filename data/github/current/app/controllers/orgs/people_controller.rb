# typed: true
# frozen_string_literal: true

class Orgs::PeopleController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:invitations_action_dialog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:destroy_members_dialog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:failed_invitations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:pending_invitations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [
      :outside_collaborators_toolbar_actions,
      :members_toolbar_actions,
      :failed_invitation_toolbar_actions,
      :pending_collaborator_invitations_toolbar_actions,
    ]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :pending_invitations, :destroy_members_dialog,
      :outside_collaborators_toolbar_actions, :invitations_action_dialog, :failed_invitations,
      :pending_collaborator_invitations_toolbar_actions,
      :members_toolbar_actions],
    optional: true

  include ActionView::Helpers::TextHelper
  include EnterpriseManagedUsersHelper

  before_action :login_required, except: :index
  before_action :organization_admin_required, except: [:index, :dismiss_org_membership_banner]
  before_action :sudo_filter, except: %i(
    cancel_pending_collaborator_invitations
    destroy_members_dialog
    destroy_invitations
    dismiss_make_direct_members_help
    dismiss_org_membership_banner
    index
    invitations_action_dialog
    failed_invitations
    failed_invitation_toolbar_actions
    members_toolbar_actions
    outside_collaborators_toolbar_actions
    pending_collaborator_invitations_toolbar_actions
    pending_invitations
    pending_invitation_toolbar_actions
    show
  )

  before_action only: %i(
    destroy_invitations
  ) do
    T.bind(self, Orgs::PeopleController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  before_action :dotcom_required, only: %i(pending_invitations failed_invitations)

  include Site::MicrosoftAnalyticsDependency
  before_action :enable_microsoft_analytics, only: [:pending_invitations]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:pending_invitations]
  layout "enterprise_funnel", only: [:pending_invitations]

  skip_before_action :cap_pagination, only: %i(index show)
  javascript_bundle :organizations

  include RepositoryControllerMethods
  include Orgs::Invitations::RateLimiting

  def index
    # if an Org is under an Enterprise Managed User enabled business
    # it is NOT viewable by non Enterprise-Managed users (including anonymous
    # requests)
    if this_organization.enterprise_managed_user_enabled?
      return render_404 unless current_user&.enterprise_managed_business == this_organization.business
    end

    set_hovercard_subject(this_organization)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/members_table", locals: {
            view: create_view_model(Orgs::People::IndexPageView,
              organization: this_organization,
              page: current_page,
              query: params[:query]
            )
          }
        elsif this_organization.has_sdn_new_org_with_free_plan_restriction?
          render "orgs/restricted_org_notice", locals: {
            target: this_organization,
            header_view: create_view_model(Orgs::HeaderView, organization: this_organization),
            selected_nav_item: :members
          }
        else
          view = create_view_model(
            Orgs::People::IndexPageView,
            organization: this_organization,
            finished_migration: params[:finished_migration] == "1",
            page: current_page,
            query: params[:query],
            rate_limited: org_invite_rate_limited?,
          )
          render "orgs/people/index", locals: { view: view }
        end
      end
    end
  end

  def show
    return render_404 if person.nil?

    repositories = this_organization.visible_repositories_for(person)

    all_repo_access = this_organization.user_all_repo_role_access(person)

    if params[:query].present?
      repositories = ActiveRecord::Base.connected_to(role: :reading) do
        filter = Organization::RepositoryFilter.new(this_organization, viewer: current_user,
                                                    phrase: params[:query], scope: repositories)
        filter.results
      end
    end

    paginated_repositories = repositories.paginate(page: current_page, per_page: 30)
    override_analytics_location "/orgs/<org-login>/people/<user-name>"

    respond_to do |format|
      format.html do
        if request.xhr?
          return render partial: "orgs/people/repository_list", locals: {
            organization: this_organization,
            person: person,
            repositories: paginated_repositories
          }
        else
          view = create_view_model(
            Orgs::People::ShowView,
            all_repo_access: all_repo_access,
            organization: this_organization,
            person: person,
            paginated_repositories: paginated_repositories,
            repositories_count: repositories.size,
          )
          render "orgs/people/show", locals: {
            view: view,
          }
        end
      end
    end
  end

  def pending_collaborator_invitations_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    selected_invitations = this_organization
      .repository_invitations
      .preload(:invitee)
      .where(id: params[:pending_collaborator_invitation_ids]&.filter_map(&:presence))

    invitees = selected_invitations.map do |invitation|
      invitation.invitee ? invitation.invitee : invitation.email
    end.uniq

    respond_to do |format|
      format.html do
        render partial: "orgs/people/pending_collaborator_invitations_toolbar_actions", locals: {
          selected_invitations: selected_invitations,
          invitees: invitees,
          organization: this_organization,
        }
      end
    end
  end

  def cancel_pending_collaborator_invitations # rubocop:todo GitHub/UseRestfulActions
    pending_collaborator_invitation_ids = params[:pending_collaborator_invitation_ids]&.filter_map(&:presence) || []

    if pending_collaborator_invitation_ids.empty?
      flash[:error] = "You must specify at least one pending collaborator."
      return redirect_to :back
    end

    invitations = this_organization
      .repository_invitations
      .where(id: pending_collaborator_invitation_ids)

    invitations.each do |invitation|
      invitation.enqueue_cancel_invitation(actor: current_user)
    end

    if invitations.empty?
      flash[:error] = "Something went wrong when canceling repository invitations for those collaborators."
    else
      flash[:notice] = "Successfully canceled #{pluralize(invitations.size, "repository invitation")}. It may take a few minutes for the removal to process."
    end

    redirect_to :back
  end

  def destroy_members_dialog # rubocop:todo GitHub/UseRestfulActions
    selected_members = this_organization.visible_users_for(current_user, actor_ids: params[:member_ids])

    respond_to do |format|
      format.html do
        render partial: "orgs/people/destroy_members_dialog", locals: {
          view: create_view_model(Orgs::People::DestroyMembersDialogView,
            organization: this_organization,
            selected_members: selected_members,
            redirect_to_path: params[:redirect_to_path]
          )
        }
      end
    end
  end

  def invitations_action_dialog # rubocop:todo GitHub/UseRestfulActions
    return render_404 if all_selected_invitations.blank?

    action_dialog = params[:action_dialog].presence

    respond_to do |format|
      format.html do
        render partial: "orgs/people/invitations_dialog", locals: {
          view: create_view_model(Orgs::People::InvitationsDialogView,
            organization: this_organization,
            selected_invitations: all_selected_invitations,
            redirect_to_path: params[:redirect_to_path],
            action_dialog: action_dialog
          )
        }
      end
    end
  end

  def destroy_failed_invitations # rubocop:todo GitHub/UseRestfulActions
    this_organization.destroy_failed_invitations(current_user)
    flash[:notice] = "You've deleted all failed invitations from #{this_organization.safe_profile_name}. It may take a few minutes to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  # Failed org invitations can be retried or deleted. Pending invitations can be cancelled.
  # Failed invitations are are due to trade restrictions in certain countries or if the invite exceeds the plan's maximum seat count
  def destroy_invitations # rubocop:todo GitHub/UseRestfulActions
    return render_404 if all_selected_invitations.blank?

    failed_or_pending_action = params[:failed_or_pending_action].presence

    # Users will be notified by email if their pending invitations are canceled
    selected_organization_invitations.each do |invitation|
      invitation.cancel(actor: current_user, notify: failed_or_pending_action == "cancelled")
    end

    selected_repository_invitations.each do |invitation|
      invitation.enqueue_cancel_invitation(actor: current_user)
    end

    flash[:notice] = "You've #{failed_or_pending_action} #{pluralize(all_selected_invitations.length, 'invitation')} from #{this_organization.safe_profile_name}. It may take a few minutes to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  def retry_failed_invitations # rubocop:todo GitHub/UseRestfulActions
    this_organization.retry_failed_invitations(current_user)
    flash[:notice] = "You've retried all failed invitations from #{this_organization.safe_profile_name}. It may take a few minutes to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  def retry_invitations # rubocop:todo GitHub/UseRestfulActions
    return render_404 if all_selected_invitations.blank?

    # Gather IDs for Bulk Reinvitations
    email_or_invitee_logins = []

    org_invitation_ids = []

    selected_organization_invitations.each do |invitation|
      invitation.cancel(actor: current_user, notify: false)
      invitation.instrument_retry_invite(actor: current_user)
      email_or_invitee_logins << invitation.email_or_invitee_login
      org_invitation_ids << invitation.id
    end

    OrganizationBulkInviteJob.perform_later \
      current_user,
      this_organization,
      email_or_invitee_logins,
      org_invitation_ids

    RepositoryBulkInviteJob.perform_later \
      current_user,
      selected_repository_invitations.map(&:id),
      this_organization.id

    # TODO: add flash messaging for ghost rows
    flash[:notice] = "You've retried #{pluralize(all_selected_invitations.length, 'invitation')} from #{this_organization.safe_profile_name}. It may take a few minutes for the retry to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  def failed_invitations # rubocop:todo GitHub/UseRestfulActions
    set_hovercard_subject(this_organization)

    view = create_view_model(
      Orgs::People::FailedInvitationsPageView,
      organization: this_organization,
      invitations: this_organization.active_failed_invitations,
      page: current_page,
      query: params[:query],
      rate_limited: org_invite_rate_limited?,
    )
    render "orgs/people/failed_invitations", locals: { view: view }
  end

  def failed_invitation_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/people/failed_invitation_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::People::FailedInvitationToolbarActionsView,
              organization: this_organization,
              selected_invitations: all_selected_invitations,
            )
          }
      end
    end
  end

  def pending_invitations # rubocop:todo GitHub/UseRestfulActions
    set_hovercard_subject(this_organization)

    view = create_view_model(
      Orgs::People::PendingInvitationsPageView,
      organization: this_organization,
      page: current_page,
      query: params[:query],
      rate_limited: org_invite_rate_limited?,
    )

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/pending_invitation_table", locals: { view: view }
        else
          render "orgs/people/pending_invitations", locals: { view: view }
        end
      end
    end
  end

  def pending_invitation_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/people/pending_invitation_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::People::PendingInvitationToolbarActionsView,
              organization: this_organization,
              selected_invitations: this_organization.pending_invitations.where(id: params[:organization_invitation_ids] || []),
              invitations_count: params[:invitations_count]
            )
          }
      end
    end
  end

  def members_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/people/members_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::People::ToolbarActionsView,
              organization: this_organization,
              selected_members: this_organization.visible_users_for(current_user, actor_ids: params[:member_ids] || [])
            )
          }
      end
    end
  end

  def outside_collaborators_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/people/outside_collaborators_toolbar_actions", locals: {
          organization: this_organization,
          selected_outside_collaborators: selected_outside_collaborators,
        }
      end
    end
  end

  private def selected_outside_collaborators
    Scientist.run("break-outside-collaborators-toolbar-actions-join") do |e|
      e.compare_record_sequence
      e.use { this_organization.outside_collaborators.where(id: params[:outside_collaborator_ids] || []).load }
      e.try do
        outside_collaborator_ids = params[:outside_collaborator_ids] || []
        ids = this_organization.outside_collaborator_ids(actor_ids: outside_collaborator_ids)
        User.where(id: ids).load
      end
    end
  end

  def dismiss_make_direct_members_help # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_notice("make_direct_members")

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def dismiss_org_membership_banner # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_notice("org_membership_banner")

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def resource_for_conditional_access
    self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_organization  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_organization
  end

  # Parses and queries using the ids of the param organization invitations, returns an array of OrganizationInvitation
  memoize def selected_organization_invitations
    # Bulk queries using the IDs from the params
    OrganizationInvitation.where(
      organization: this_organization,
      id: (params[:organization_invitation_ids]&.split(",") || []),
      accepted_at: nil,
      cancelled_at: nil
    )
  end

  # Parses and queries using the ids of the param repository invitations, returns an array of RepositoryInvitation
  memoize def selected_repository_invitations
    this_organization.repository_invitations.where(id: (params[:repository_invitation_ids]&.split(",") || []))
  end

  # Parses and queries using the ids of the original invitations, returns an array of all combined invitations
  def all_selected_invitations
    selected_organization_invitations + selected_repository_invitations
  end

  # Helper method to determine view parameter name for a given set of
  # invitation IDs, when we need to discriminate between different
  # invitation types
  def invitation_id_param_name(invitation)
    case invitation
    when OrganizationInvitation
      "organization_invitation_ids[]"
    when RepositoryInvitation
      "repository_invitation_ids[]"
    end
  end
  helper_method :invitation_id_param_name
end
