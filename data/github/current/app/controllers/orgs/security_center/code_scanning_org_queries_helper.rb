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

    build_alert_query_service(allowed_repository_ids: allowed_repo_ids)
  end

  sig { returns(CodeScanning::AlertQueryService) }
  memoize def alert_query_service_with_repositories_from_params
    allowed_repo_ids = repository_ids_from_params

    if allowed_repo_ids.nil?
      allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded
    end

    build_alert_query_service(allowed_repository_ids: allowed_repo_ids)
  end

  sig { params(allowed_repository_ids: T.nilable(T::Array[Integer])).returns(CodeScanning::AlertQueryService) }
  def build_alert_query_service(allowed_repository_ids:)
    CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: user_session,
      organization: this_organization,
      allowed_repository_ids:,
      query: query_string,
      visibility: limited_visibility? ? "public" : nil,
      security_campaign_ids: security_campaign_id.nil? ? nil : [T.must(security_campaign_id)]
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

  sig { returns(T.nilable(Integer)) }
  memoize def security_campaign_id
    return unless params[:security_campaign_number].present?

    published_campaigns = SecurityCampaigns::SecurityCampaign.published
    published_campaigns = published_campaigns.filter_spam_for(current_user)
    campaign = published_campaigns.find_by(number: params[:security_campaign_number].to_i, organization: this_organization)
    return if campaign.nil?

    campaign.id
  end

  # Returns the repository IDs from the `repository` param. Returns nil if the param is not present or empty.
  # Returns an empty array if the param is invalid or the user does not have access to any of the repositories.
  # This matches the expected format of the allowed_repository_ids param on the alert query service.
  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def repository_ids_from_params
    repository_names = Array(params[:repository])
    return nil if repository_names.empty?
    # Do not allow more than 1000 repositories to be specified in the query params
    return [] if repository_names.size > 1000

    # We can only find repositories by nwo through the public interface, so just add the owner to the name
    repository_nwos = repository_names.map { |name| "#{this_organization.display_login}/#{name}" }

    repository_ids = Repository.with_names_with_owners(repository_nwos).pluck(:id)

    # Check that the user has code scanning read access to the repositories
    repository_ids = SecurityProduct::AuthorizationEnumerator.new(user: current_user, actions: [:read_code_scanning], options: {
      organization: this_organization,
      repository_ids:,
    }).authorized_repository_ids

    repository_ids
  end
end
