# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PendingOwnersController < Stafftools::Businesses::BusinessBaseController
  before_action :check_for_owners, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    invitations = this_business.pending_admin_invitations(query: params[:query], role: [:owner])
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/pending_owners", locals: { pending_owner_invitations: invitations }
  end

  def destroy
    invitation = this_business.invitations.pending.with_business_role(:owner)
      .find_by!(id: params[:invitation_id])
    invitation.cancel actor: current_user

    flash[:notice] = \
      "You've canceled #{invitation.email_or_invitee_name}'s invitation to become #{invitation.role_for_message} of #{invitation.business.name}."
    redirect_to stafftools_enterprise_pending_owners_path(this_business)
  end
end
