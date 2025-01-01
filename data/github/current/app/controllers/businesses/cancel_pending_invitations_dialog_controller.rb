# typed: true
# frozen_string_literal: true

class Businesses::CancelPendingInvitationsDialogController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :manage_enterprise_invitations_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :selected_invitations_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    respond_to do |format|
      format.html do
        render Businesses::People::PendingInvitationsDialogViewComponent.new(
          this_business: this_business,
          selected_invitations: selected_invitations,
          redirect_to_path: redirect_to_path,
          opts: { invitation_type: invitation_type }
        ), layout: false
      end
    end
  end

  private

  def selected_invitations_required
    render_404 if selected_invitations.empty?
  end

  memoize def invitation_type
    params[:invitation_type]
  end

  memoize def selected_invitations
    case invitation_type
    when "member"
      this_business.pending_member_invitations.where(id: params[:invitation_ids] || [])
    when "collaborator"
      this_business.pending_collaborator_invitations.where(id: params[:invitation_ids] || [])
    when "admin"
      this_business.pending_admin_invitations.where(id: params[:invitation_ids] || [])
    when "unaffiliated"
      this_business.pending_unaffiliated_invitations.where(id: params[:invitation_ids] || [])
    end
  end

  memoize def redirect_to_path
    case invitation_type
    when "member"
      enterprise_pending_members_path(this_business)
    when "collaborator"
      enterprise_pending_collaborators_path(this_business)
    when "admin"
      enterprise_pending_admins_path(this_business)
    when "unaffiliated"
      enterprise_pending_unaffiliated_members_path(this_business)
    end
  end
end
