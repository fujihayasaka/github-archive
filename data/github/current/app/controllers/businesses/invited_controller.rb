# typed: true
# frozen_string_literal: true

class Businesses::InvitedController < Businesses::BusinessController
  include BusinessesHelper

  before_action :dotcom_required
  before_action :login_required
  before_action :invitation_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    invitation = BusinessOrganizationInvitation.pending.where(
      business: this_business,
      invitee_id: current_user.owned_organization_ids
    ).first
    render "businesses/invited", locals: { invitation: invitation }
  end

  private

  def invitation_required
    return if BusinessOrganizationInvitation.pending.where(
      business: this_business,
      invitee_id: current_user.owned_organization_ids
    ).any?
    render_404
  end
end
