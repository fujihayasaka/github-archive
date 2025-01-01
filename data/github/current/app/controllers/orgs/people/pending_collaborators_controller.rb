# typed: true
# frozen_string_literal: true

class Orgs::People::PendingCollaboratorsController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action :dotcom_required, only: :index

  javascript_bundle :organizations

  def index
    invitations = pending_collaborators_invitations_scope
      .order(email: :desc, created_at: :desc)
      .paginate(page: params[:page], per_page: 30)

    invitees = invitations.map { |invitation| invitation.invitee ? invitation.invitee : invitation.email }.uniq

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/pending_collaborator_invitations_list",
            locals: {
              view: create_view_model(Orgs::People::PendingCollaboratorInvitationsListView,
                organization: this_organization,
                invitations: invitations,
                invitees: invitees
              )
            }
        else
          render "orgs/people/pending_collaborator_invitations", locals: {
            organization: this_organization,
            invitations: invitations,
            invitees: invitees
          }
        end
      end
    end
  end

  def destroy
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
end
