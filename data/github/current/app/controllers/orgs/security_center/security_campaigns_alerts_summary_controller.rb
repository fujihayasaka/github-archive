# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsAlertsSummaryController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::AlertResultsHelper
  include SecretScanning::SecurityCampaigns::SecretScanningAlertResultsHelper
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer

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
    alert_type = params[:alert_type] || "code_scanning"

    if alert_type == "secret_scanning"
      secret_scanning_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: params[:query])
      return render status: 422, json: { message: "Invalid query" } unless secret_scanning_query.is_valid?

      alert_results_by_repo, has_error = secret_scanning_alerts_from_query(secret_scanning_query)
      return render status: 500, json: { message: "Failed to fetch secret scanning alerts to include in the campaign. Please reload and try again." } if has_error
      return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if alert_results_by_repo.empty?

      repositories = Repository.where(id: alert_results_by_repo.keys).index_by(&:id)
      repositories_payload = alert_results_by_repo.filter_map do |repository_id, alert_numbers|
        repository = repositories[repository_id]
        next unless repository

        build_repository_payload(repository, alert_numbers.size)
      end
    else
      code_scanning_query = Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(params[:query])
      return render status: 422, json: { message: "Invalid query" } unless code_scanning_query.is_valid?

      alert_results, has_error = alert_results_from_query(code_scanning_query)
      return render status: 500, json: { message: "Failed to fetch alerts to include in the campaign. Please reload and try again." } if has_error
      return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if alert_results.empty?

      repositories = alert_results.map(&:repository).uniq.index_by(&:id)
      alerts = security_campaigns_alerts_from_alert_results(alert_results)
      repositories_payload = alerts.filter_map do |repository_id, alert_numbers|
        repository = repositories[repository_id]
        next unless repository

        build_repository_payload(repository, alert_numbers.size)
      end
    end

    render json: { repositories: repositories_payload }
  end

  private

  def build_repository_payload(repository, alert_count)
    {
      repository: serialized_repository(repository:),
      alertCount: alert_count,
      issuesEnabled: repository.has_issues,
    }
  end
end
