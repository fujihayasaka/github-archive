# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsAlertsSummaryController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::AlertResultsHelper
  include ApplicationController::VerifiedFetchDependency
  include SecurityCampaigns::RepositoriesSerializer

  before_action :manage_security_products_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:index]

  allow_verified_fetch only: [:index]

  def index
    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    alert_results, has_error = alert_results_from_query(query)
    return render status: 500, json: { message: "Failed to fetch alerts to include in the campaign. Please reload and try again." } if has_error
    return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if alert_results.empty?

    repositories = alert_results.map(&:repository).uniq.index_by(&:id)

    alerts = security_campaigns_alerts_from_alert_results(alert_results)

    repositories_payload = alerts.map do |repository_id, alert_numbers|
      repository = repositories[repository_id]
      next unless repository

      {
        repository: serialized_repository(repository:),
        alertCount: alert_numbers.size,
      }
    end.compact

    render json: {
      repositories: repositories_payload,
    }
  end
end
