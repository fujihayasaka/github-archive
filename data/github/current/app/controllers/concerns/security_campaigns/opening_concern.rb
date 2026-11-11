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

    generate_issues = T.let(ActiveModel::Type::Boolean.new.cast(params.fetch(:campaign_generate_issues, false)), T::Boolean) && SecurityCampaigns.issue_creation_enabled?(org)

    source_campaign_id = params[:source_campaign_id]&.to_i

    alert_type = alert_type.present? ? alert_type : params[:alert_type] || "code_scanning"
    return render status: 422, json: { message: "Unknown alert_type" } unless SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(alert_type)

    if generate_issues && alert_type == "secret_scanning"
      return render status: 422, json: { message: "Cannot generate issues for secret scanning campaigns" }
    end

    if alert_type == "secret_scanning"
      secret_scanning_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: query_string)
      if !secret_scanning_query.is_valid?
        log_secret_scanning_campaign_opening_failure(reason: "invalid_query", secret_scanning_query: secret_scanning_query)
        return render status: 422, json: { message: "Invalid query" }
      end

      secret_scanning_alert_results, has_error = secret_scanning_alerts_from_query(secret_scanning_query)
      if has_error
        log_secret_scanning_campaign_opening_failure(reason: "fetch_error", secret_scanning_query: secret_scanning_query)
        return render status: 500, json: { message: "Failed to fetch secret scanning alerts to include in the campaign. Please reload and try again." }
      end
      if secret_scanning_alert_results.empty?
        log_secret_scanning_campaign_opening_failure(reason: "empty_results", secret_scanning_query: secret_scanning_query)
        return render status: 422, json: { message: "Could not find any secret scanning alerts to include in the campaign. Please reload and try again." }
      end
    else
      code_scanning_query = Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query_string)
      return render status: 422, json: { message: "Invalid query" } if !code_scanning_query.is_valid?

      code_scanning_alert_results, has_error = alert_results_from_query(code_scanning_query)
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
      code_scanning_alerts:,
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

  private

  sig { params(value: T.untyped, max_bytes: Integer).returns(T.untyped) }
  def truncate_query(value, max_bytes: 500)
    return value unless value.is_a?(String)
    return value if value.bytesize <= max_bytes

    value.byteslice(0, max_bytes)
  end

  sig { returns(T::Boolean) }
  def security_campaigns_diagnostic_logging_enabled?
    FeatureFlag.vexi.enabled?(
      :security_campaigns_secret_scanning_opening_failure_logging,
      current_user,
      T.must(this_organization),
      T.must(this_organization).business,
      default: false,
    )
  rescue StandardError
    false
  end

  sig { params(reason: String, secret_scanning_query: Search::Queries::SecurityCenter::SecretScanningQuery).void }
  def log_secret_scanning_campaign_opening_failure(reason:, secret_scanning_query:)
    return unless security_campaigns_diagnostic_logging_enabled?

    repository_ids, limit_exceeded = allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::SECRET_SCANNING]
    query = query_string

    query_truncated = truncate_query(query)
    params_query_truncated = truncate_query(params[:query])

    payload = {
      reason:,
      controller: self.class.name,
      action: (respond_to?(:action_name) ? action_name : nil),
      path: (respond_to?(:request) ? request.path : nil),
      request_id: (respond_to?(:request) ? request.request_id : nil),

      "code.namespace": self.class.name,
      "code.function": "campaign_opening_details_from_params",
      "controller.name": self.class.name,
      "controller.action": (respond_to?(:action_name) ? action_name : nil),

      organization_id: T.must(this_organization).id,
      organization_login: T.must(this_organization).display_login,
      actor_id: (respond_to?(:current_user) && current_user ? current_user.id : nil),
      alert_type: (params[:alert_type] || "secret_scanning"),
      campaign_number: params[:number],
      query_string: query_truncated,
      params_query: params_query_truncated,
      params_query_present: params.key?(:query),
      repo_ids_count: repository_ids&.size,
      repo_ids_limit_exceeded: limit_exceeded,
      repo_ids_sample: repository_ids&.first(10),
      query_valid: secret_scanning_query.is_valid?,
      query_results_category: secret_scanning_query.results_category,
      query_validities: secret_scanning_query.validities_strings,
    }

    case reason
    when "fetch_error"
      GitHub.logger.error("security_campaigns.secret_scanning_campaign_opening_failed", **payload)
    else
      GitHub.logger.warn("security_campaigns.secret_scanning_campaign_opening_failed", **payload)
    end
  rescue StandardError => e
    GitHub.logger.warn("security_campaigns.secret_scanning_campaign_opening_failed_logging_error", reason: reason, error_class: e.class.name)
  end
end
