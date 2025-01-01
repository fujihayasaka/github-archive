# typed: true
# frozen_string_literal: true

module Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  extend T::Helpers

  requires_ancestor { Orgs::SecurityCenter::AbstractSecurityCenterController }

  include GitHub::Memoizer

  abstract!

  # @return [Array<Array<Integer>, boolean>, Array<nil, nil>]
  #   Array elements:
  #     0: IDs for repositories the user is allowed to access.
  #     1: Whether or not number of repos the user is allowed access exceeds the limit.
  #
  #   If Array<nil, nil>, the user has access to all repositories.
  memoize def allowed_repo_ids_and_limit_exceeded
    return [nil, nil] if can_view_all_alerts?

    allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::CODE_SCANNING]
  end

  sig { returns(CodeScanning::AlertQueryService) }
  memoize def alert_query_service
    allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded

    CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: user_session,
      organization: this_organization,
      allowed_repository_ids: allowed_repo_ids,
      query: query_string,
      visibility: limited_visibility? ? "public" : nil,
      repo_numbers:
    )
  end

  memoize def limited_visibility?
    SecurityCenter::SecurityFeatures.limited_security_center_available?(this_organization, dotcom_request_only: true)
  end

  memoize def query_string
    params[:query]&.strip || "is:open"
  end

  memoize def query
    Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query_string)
  end

  sig { returns(T.nilable(T::Array[Turboscan::Proto::RepoNumber])) }
  memoize def repo_numbers
    return unless params[:security_campaign_number].present?

    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:security_campaign_number].to_i, organization: this_organization)
    return if campaign.nil?

    security_campaign_alerts = SecurityCampaigns::SecurityCampaignAlert.where(security_campaign_id: campaign.id)
    SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(security_campaign_alerts.to_a)
  end
end
