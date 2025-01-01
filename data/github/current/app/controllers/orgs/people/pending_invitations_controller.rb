# typed: true
# frozen_string_literal: true

class Orgs::People::PendingInvitationsController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action :dotcom_required, only: :index

  include Site::MicrosoftAnalyticsDependency
  before_action :enable_microsoft_analytics, only: :index
  before_action :add_microsoft_analytics_csp_exceptions, only: :index
  layout "enterprise_funnel", only: :index

  javascript_bundle :organizations

  before_action only: :destroy do
    T.bind(self, Orgs::People::PendingInvitationsController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  include Orgs::Invitations::RateLimiting

  def index
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

  def update
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

  # Failed org invitations can be retried or deleted. Pending invitations can be cancelled.
  # Failed invitations are are due to trade restrictions in certain countries or if the invite exceeds the plan's maximum seat count
  def destroy
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
end
