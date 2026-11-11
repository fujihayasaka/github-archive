# typed: true
# frozen_string_literal: true

class Orgs::People::TabCountsController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :login_required
  before_action :require_xhr

  def index
    results = {}

    if params[:member].present?
      results[".unstyled-orgs-member-count"] = this_organization.visible_user_ids_for(current_user, limit: nil).size
    end

    if this_organization.adminable_by?(current_user)
      if params[:guest_collaborator].present?
        results[".unstyled-orgs-guest-collabo-count"] = this_organization.guest_collaborators.size
      end

      if params[:outside_collabo].present?
        results[".unstyled-orgs-outside-collabo-count"] = this_organization.outside_collaborators.size
      end

      if params[:pending_collabo].present?
        results[".unstyled-orgs-pending-collabo-count"] = pending_collaborators_invitations_scope.size
      end

      if params[:pending_invite].present? &&
        results[".unstyled-orgs-pending-invite-count"] = this_organization.pending_non_manager_invitations.size
      end

      if params[:failed_invite].present?
        results[".unstyled-orgs-failed-invite-count"] = this_organization.active_failed_invitations_count
      end
    end

    if params[:enterprise_owner].present? &&
      this_organization.business.present? &&
      this_organization.direct_or_team_member?(current_user)

      results[".unstyled-enterprise-owners-count"] = this_organization.business.admins(role: :owner).size
    end

    if params[:security_manager].present? && this_organization.direct_or_team_member?(current_user)
      results[".unstyled-security-mangers-count"] = SecurityProduct::SecurityManagers.new(this_organization).users.count
    end

    render json: { selectors: results }
  end
end
