# typed: strict
# frozen_string_literal: true

class EnterpriseTeamGroupSuggestionsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include BusinessTeamHandlers

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify

  before_action :enterprise_teams_enabled_required
  before_action :business_owner_required

  # GET /enterprises/:slug/team_group_suggestions
  # Returns a JSON response with IdP group data
  sig { void }
  def index
    # Check if IdP groups are available for this enterprise
    enterprise = this_business
    unless enterprise.external_provider && idp_groups_available?
      return render(json: { error: "IdP groups not available" }, status: :not_found)
    end

    groups = enterprise.external_provider
      .external_groups
      .not_deleted
      .order_by_display_name_asc

    if params[:q].present?
      groups = groups.like_display_name(params[:q])
    end

    # Apply limit if provided, default to 500
    limit = params[:limit].present? ? params[:limit].to_i : 500
    groups = groups.limit(limit) if limit.positive?

    group_ids_with_guest_collaborator = ExternalGroup.external_group_ids_with_guest_collaborator(groups.pluck(:id))

    groups_data = groups.map do |group|
      {
        id: group.id,
        displayName: group.display_name,
        hasGuestCollaborators: group_ids_with_guest_collaborator.include?(group.id)
      }
    end

    render json: { groups: groups_data }
  end

  private

  sig { void }
  def enterprise_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business)
  end
end
