# typed: true
# frozen_string_literal: true

class Orgs::People::InvitationsActionDialogController < Orgs::Controller
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
  javascript_bundle :organizations

  def show
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
end
