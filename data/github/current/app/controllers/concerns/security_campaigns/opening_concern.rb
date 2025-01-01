# typed: true
# frozen_string_literal: true

module SecurityCampaigns::OpeningConcern
  include SecurityCampaigns::ManagersDependency
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include Orgs::SecurityCenter::SecretScanningOrgQueriesHelper
  include SecurityCampaigns::AlertResultsHelper
  include SecretScanning::SecurityCampaigns::SecretScanningAlertResultsHelper

  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  # Processes the details for opening a campaign, including validating input parameters and fetching alerts.
  # Returns a CampaignOpeningDetails object or an error.
  sig do
    params(org: Organization, user: User, alert_type: T.nilable(String)).
    returns(T.any(SecurityCampaigns::CampaignOpeningDetails, String))
  end
  def campaign_opening_details_from_params(org, user, alert_type = nil)
    return render status: 422, json: { message: "Campaign name required" } if params[:campaign_name].blank?
    return render status: 422, json: { message: "Campaign description required" } if params[:campaign_description].blank?
    return render status: 422, json: { message: "Campaign due date required" } if params[:campaign_due_date].blank?

    managers = prepare_managers(org)
    return managers unless managers.is_a?(Array)

    team_managers = prepare_team_managers(org)
    return team_managers unless team_managers.is_a?(Array)

    managers_validation = validate_number_campaign_managers(user_manager_ids: managers.map(&:id), team_manager_ids: team_managers.map(&:id))
    return managers_validation if managers_validation.is_a?(String)

    contact_link = params[:campaign_contact_link]

    ends_at = Time.zone.parse(params[:campaign_due_date])
    return render status: 400, json: { message: "Invalid due date" } if ends_at.blank? || ends_at < Time.zone.now

    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    generate_issues = T.let(ActiveModel::Type::Boolean.new.cast(params.fetch(:campaign_generate_issues, false)), T::Boolean) && SecurityCampaigns.issue_creation_enabled?(org)

    source_campaign_id = params[:source_campaign_id]&.to_i

    alert_type = alert_type.present? ? alert_type : params[:alert_type] || "code_scanning"
    return render status: 422, json: { message: "Unknown alert_type" } unless SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(alert_type)

    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    if alert_type == "secret_scanning"
      secret_scanning_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: query_string)
      secret_scanning_alert_results, has_error = secret_scanning_alerts_from_query(secret_scanning_query)
      return render status: 500, json: { message: "Failed to fetch secret scanning alerts to include in the campaign. Please reload and try again." } if has_error
      return render status: 422, json: { message: "Could not find any secret scanning alerts to include in the campaign. Please reload and try again." } if secret_scanning_alert_results.empty?
    else
      code_scanning_alert_results, has_error = alert_results_from_query(query)
      return render status: 500, json: { message: "Failed to fetch alerts to include in the campaign. Please reload and try again." } if has_error
      return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if code_scanning_alert_results.empty?
    end

    code_scanning_alerts = code_scanning_alert_results.present? ? security_campaigns_alerts_from_alert_results(code_scanning_alert_results) : {}
    secret_scanning_alerts = secret_scanning_alert_results.present? ? secret_scanning_alert_results : {}

    SecurityCampaigns::CampaignOpeningDetails.new(
      org:,
      name: params[:campaign_name],
      description: params[:campaign_description],
      query_string:,
      alert_type:,
      alerts: code_scanning_alerts,
      secret_scanning_alerts:,
      ends_at:,
      managers:,
      team_managers:,
      contact_link:,
      generate_issues:,
      source_campaign_id:,
      created_by: user,
    )
  end

  # Builds a message to use in a flash notice to notify the user about the opening of a campaign and the subsequent actions.
  sig { params(opening_details: SecurityCampaigns::CampaignOpeningDetails, operation: String).returns(T.nilable(String)) }
  def campaign_open_flash_message(opening_details, operation)
    generate_issues = opening_details.generate_issues

    if generate_issues
      "Campaign successfully #{operation}. Generating issues for all repositories in this campaign."
    else
      "Campaign successfully #{operation}."
    end
  end
end
