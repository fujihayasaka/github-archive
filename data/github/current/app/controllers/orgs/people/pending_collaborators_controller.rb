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
  before_action :dotcom_required

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
end
