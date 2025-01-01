# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is created and creates the security campaign alerts in turboscan.
  # This is part of a spike to try a new data model for security campaign alerts https://github.com/github/code-scanning/issues/16287
  class CreateSecurityCampaignAlertsJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(security_campaign_id: Integer, query_string: String, user_id: Integer, organization_id: Integer, user_session_id: T.nilable(Integer)).void }
    def perform(security_campaign_id:, query_string:, user_id:, organization_id:, user_session_id:)
      return unless security_campaign_id.present?

      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: security_campaign_id)

      return if campaign.nil?

      alert_results = T.let([], T::Array[CodeScanning::AlertResult])

      user = User.find_by(id: user_id)
      user_session = UserSession.find_by(id: user_session_id) unless user_session_id.nil?
      organization = Organization.find_by(id: organization_id)

      return if user.nil? || user_session.nil? || organization.nil?

      alert_query_service = alert_query_service(user:, user_session:, organization:, query: query_string)
      cursor = T.let(nil, T.nilable(String))

      # All alerts may be filtered out by the additonal check on repository visibility, so we need to ensure we don't
      # get stuck in an infinite loop. This also enforces an alert limit of 100k.
      max_requests = 1000
      requests = 0

      while requests < max_requests
        page_alert_results, _, has_error, response = alert_query_service.alerts_by_repo_with_response(
          after_cursor: cursor,
          per_page: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
        )

        if has_error
          return
        end

        repo_numbers = page_alert_results.map do |alert|
          {
            repository_id: alert.repository.id,
            number: alert.result.number,
          }
        end

        GitHub::Turboscan.create_security_campaign_alerts(security_campaign_id:, repo_numbers:)


        cursor = response.try(:data).try(:next_cursor)

        if cursor.blank?
          # If we receive an empty next cursor, there are no more results on the next pages.
          return
        end

        requests += 1
      end
    end

    sig { params(user: User, user_session: T.nilable(UserSession), organization: Organization, query: String).returns(CodeScanning::AlertQueryService) }
    def alert_query_service(user:, user_session:, organization:, query:)
      allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded(user:, organization:)

      CodeScanning::AlertQueryService.for_organization(
        user:,
        user_session:,
        organization:,
        allowed_repository_ids: allowed_repo_ids,
        query:,
      )
    end

    sig { params(user: User, organization: Organization).returns(T.nilable([T.nilable(T::Array[Integer]), T.nilable(T::Boolean)])) }
    def allowed_repo_ids_and_limit_exceeded(user:, organization:)
      return [nil, nil] if can_manage_security_products?(user:, organization:)

      allowed_repository_ids_by_feature_for_organization_members(user:, organization:)[SecurityCenter::SecurityFeatures::CODE_SCANNING]
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def can_manage_security_products?(user:, organization:)
      SecurityProduct::Permissions::OrgAuthz.new(organization, actor: user).can_manage_security_products?
    end

    sig { params(user: User, organization: Organization).returns(T::Hash[String, [T::Array[Integer], T::Boolean]]) }
    def allowed_repository_ids_by_feature_for_organization_members(user:, organization:)
      auth_enumerator(user:, organization:).allowed_repository_ids_by_feature_for_organization_member
    end

    sig { params(user: User, organization: Organization).returns(SecurityCenter::AuthorizationEnumerator) }
    def auth_enumerator(user:, organization:)
      SecurityCenter::AuthorizationEnumerator.new(
        user:,
        org: organization,
      )
    end
  end
end
