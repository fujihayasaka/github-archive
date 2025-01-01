# typed: true
# frozen_string_literal: true

class Orgs::People::PendingCollaboratorInvitationActionsController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  before_action :login_required
  before_action :organization_admin_required

  def show
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
end
