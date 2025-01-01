# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ReviewableOrganizationInvitationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :business_required, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/organization_invitations_list", layout: "stafftools", locals: {
      pending_completion_invitations: BusinessOrganizationInvitation
        .pending_completion
        .joins(:business, :invitee)
        .order("confirmed_at DESC")
        .paginate(page: current_page(:pending_page), per_page: DEFAULT_PAGE_SIZE),
      completed_invitations: BusinessOrganizationInvitation
        .with_status(:completed)
        .joins(:business, :invitee)
        .includes(:completed_by)
        .order("completed_at DESC")
        .paginate(page: current_page(:reviewed_page), per_page: DEFAULT_PAGE_SIZE)
    }
  end

  def update
    begin
      this_business.organization_invitations.pending_completion.find(params[:invitation_id]).complete(current_user)
      flash[:notice] = "Marked invitation as completed."
    rescue BusinessOrganizationInvitation::CanceledError
      flash[:error] = "This invitation has been canceled."
    rescue BusinessOrganizationInvitation::NotYetConfirmedError
      flash[:error] = "This invitation has not yet been confirmed."
    rescue BusinessOrganizationInvitation::AlreadyCompletedError
      flash[:error] = "This invitation has already been completed."
    end
    redirect_to organization_invitations_stafftools_enterprises_path
  end
end
