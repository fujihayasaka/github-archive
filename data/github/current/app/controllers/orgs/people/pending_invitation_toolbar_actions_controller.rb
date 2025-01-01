# typed: true
# frozen_string_literal: true

class Orgs::People::PendingInvitationToolbarActionsController < Orgs::Controller
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
end
