# typed: strict
# frozen_string_literal: true

class Businesses::BusinessTeamOrganizationSuggestionsController < Businesses::BusinessController
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  allow_verified_fetch only: [:index]
  before_action :business_owner_required
  before_action :business_teams_enabled_required
  before_action :business_validate_team_parameter

  sig { void }
  def index
    organization_suggestions(params[:query], business_team.organization_ids)
  end

  private

  sig { void }
  def business_teams_enabled_required
    render_404 unless current_business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end
end
