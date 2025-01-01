# typed: true
# frozen_string_literal: true

class Businesses::FailedInvitationsActionDialogController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: %i(show),
    optional: true

  def show
    action_dialog = params[:action_dialog].presence
    invitation_ids = params[:invitation_ids].presence
    return render_404 if action_dialog.blank? || invitation_ids.blank?

    selected_invitations = this_business.failed_invitations.select { |invite| invitation_ids.flatten.include?(invite.id.to_s) }
    return render_404 if selected_invitations.blank?

    return render_404 unless %w(cancel delete retry).include?(action_dialog)

    respond_to do |format|
      format.html do
        render Businesses::People::FailedInvitationDialogComponent.new(
          business: this_business,
          selected_invitations: selected_invitations,
          redirect_to_path: params[:redirect_to_path],
          action_dialog: action_dialog
        ), layout: false
      end
    end
  end
end
