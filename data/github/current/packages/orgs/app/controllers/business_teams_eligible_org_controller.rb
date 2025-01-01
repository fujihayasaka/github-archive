# typed: strict
# frozen_string_literal: true

class BusinessTeamsEligibleOrgController < Businesses::BusinessController
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "BusinessTeamsEligibleOrgController#index",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  allow_verified_fetch only: [:index]
  before_action :business_owner_required
  before_action :business_teams_enabled_required
  before_action :validate_params, only: [:index]

  sig { void }
  def index
    organization_suggestions(query_params["query"], query_params["selectedOrganizationIds"])
  end

  private

  sig { void }
  def business_teams_enabled_required
    render_404 unless current_business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def query_params
    JSON.parse(request&.body.read)
  end

  sig { void }
  def validate_params
    begin
      selected_organization_ids = query_params["selectedOrganizationIds"]
    rescue JSON::ParserError
      return render(json: { error: "Invalid json body" }, status: :bad_request)
    end
    return if selected_organization_ids.nil?
    unless selected_organization_ids.is_a?(Array) && selected_organization_ids.all? { |id| id.is_a?(Integer) }
      render(json: { error: "selectedOrganizationIds must be an array of numbers" }, status: :bad_request)
    end
  end
end
