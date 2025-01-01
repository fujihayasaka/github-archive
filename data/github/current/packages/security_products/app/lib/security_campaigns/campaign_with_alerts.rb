# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This class contains a security campaign enriched with full alert data
  # from turboscan.
  class CampaignWithAlerts < CampaignBase

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, turboscan_alerts: T::Array[CodeScanning::AlertResult], counts: CampaignCounts, next_cursor: T.nilable(String), prev_cursor: T.nilable(String), has_error: T::Boolean).void }
    def initialize(security_campaign:, turboscan_alerts:, counts:, next_cursor:, prev_cursor:, has_error:)
      super(security_campaign, counts)
      @turboscan_alerts = turboscan_alerts
      @next_cursor = next_cursor
      @prev_cursor = prev_cursor
      @has_error = has_error
    end

    sig { returns(T::Array[CodeScanning::AlertResult]) }
    attr_reader :turboscan_alerts

    sig { returns(T.nilable(String)) }
    attr_reader :next_cursor

    sig { returns(T.nilable(String)) }
    attr_reader :prev_cursor

    sig { returns(T::Boolean) }
    attr_reader :has_error

    sig { returns(T::Array[CodeScanning::RepoAlertTuple]) }
    def repo_alert_tuples
      turboscan_alerts.map do |alert|
        CodeScanning::RepoAlertTuple.new(repository_id: alert.repository.id, alert_number: alert.result.number)
      end.uniq
    end

    # Load alerts for the specified security campaign and enrich it with alerts from turboscan
    # The repository is optional, if not specified then all repositories are loaded
    # The alert_numbers are optional, if not specified then all alerts are loaded
    # The query is optional, if not specified then all alerts are loaded
    # After and before are cursors to load the next/previous page of alerts. Only 1 of them should be specified.
    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        user: User,
        user_session: UserSession,
        repo: T.nilable(Repository),
        alert_numbers: T::Hash[Integer, T::Array[Integer]],
        query_string: T.nilable(String),
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns(CampaignWithAlerts)
    end
    def self.load_campaign(security_campaign, user:, user_session:, repo: nil, alert_numbers: {}, query_string: nil, after_cursor: nil, before_cursor: nil)
      query_service_params = {
        user:,
        user_session:,
        org: T.must(security_campaign.organization),
        repo:,
        query_string:,
        repo_numbers: nil,
      }

      repo_numbers = if alert_numbers.empty?
        nil
      else
        alert_numbers.flat_map do |repository_id, numbers|
          numbers.map do |number|
            Turboscan::Proto::RepoNumber.new(repository_id:, number:)
          end
        end
      end
      alert_query_service = alert_query_service(**query_service_params.merge(
        security_campaign_ids: [security_campaign.id]),
        repo_numbers:,
      )
      load_turboscan_alerts(security_campaign, alert_query_service:, after_cursor:, before_cursor:)
    end

    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        alert_query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns(CampaignWithAlerts)
    end
    def self.load_turboscan_alerts(security_campaign, alert_query_service:, after_cursor:, before_cursor:)
      tags = ["kind:turboscan_alerts_all_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        alert_results, has_error, alerts_response = code_scanning_alerts_for_alert_numbers(
          alert_query_service:,
          after_cursor:,
          before_cursor:,
        )

        turboscan_results = alerts_response&.data&.try(:results) || []
        open_count = T.let(alerts_response&.data&.try(:open_count) || 0, Integer)
        closed_count = T.let(alerts_response&.data&.try(:resolved_count) || 0, Integer)
        open_with_links_count = T.let(alerts_response&.data&.try(:open_with_links_count) || 0, Integer)
        counts = CampaignCounts.new(open_count:, closed_count:, open_with_links_count:)
        next_cursor = T.let(alerts_response&.data&.try(:next_cursor), T.nilable(String))
        prev_cursor = T.let(alerts_response&.data&.try(:prev_cursor), T.nilable(String))

        CampaignWithAlerts.new(
          security_campaign:,
          turboscan_alerts: alert_results,
          counts:,
          next_cursor:,
          prev_cursor:,
          has_error:,
        )
      end
    end

    sig do
      params(
        alert_query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns([T::Array[CodeScanning::AlertResult], T::Boolean, T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsByRepoResponse)])])
    end
    def self.code_scanning_alerts_for_alert_numbers(alert_query_service:, after_cursor:, before_cursor:)
      tags = ["kind:turboscan_alerts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        alert_results, _, has_error, response = alert_query_service.alerts_by_repo_with_response(per_page: page_size, before_cursor:, after_cursor:)

        [alert_results, has_error, response]
      end
    end

    # Returns the page size to use for pagination
    sig { returns(Integer) }
    def self.page_size
      25
    end

    private

    sig do
      params(
        user: User,
        user_session: UserSession,
        org: Organization,
        repo: T.nilable(Repository),
        query_string: T.nilable(String),
        repo_numbers: T.nilable(T::Array[Turboscan::Proto::RepoNumber]),
        security_campaign_ids: T.nilable(T::Array[Integer]),
      ).returns(CodeScanning::AlertQueryService)
    end
    private_class_method def self.alert_query_service(user:, user_session:, org:, repo:, query_string:, repo_numbers:, security_campaign_ids: nil)
      allowed_repo_ids = if repo.present?
        [repo.id]
      else
        allowed_repo_ids_and_limit_exceeded(user:, org:)&.first
      end

      CodeScanning::AlertQueryService.for_organization(
        user: user,
        user_session: user_session,
        organization: org,
        allowed_repository_ids: allowed_repo_ids,
        query: query_string,
        repo_numbers:,
        security_campaign_ids:,
      )
    end

    sig { params(user: User, org: Organization).returns(SecurityCenter::AuthorizationEnumerator) }
    private_class_method def self.auth_enumerator(user:, org:)
      SecurityCenter::AuthorizationEnumerator.new(user:, org:)
    end

    sig { params(user: User, org: Organization).returns(T::Hash[String, [T::Array[Integer], T::Boolean]]) }
    private_class_method def self.allowed_repository_ids_by_feature_for_organization_members(user:, org:)
      auth_enumerator(user:, org:).allowed_repository_ids_by_feature_for_organization_member
    end

    # @return [Array<Array<Integer>, boolean>, Array<nil, nil>]
    #   Array elements:
    #     0: IDs for repositories the user is allowed to access.
    #     1: Whether or not number of repos the user is allowed access exceeds the limit.
    #
    #   If Array<nil, nil>, the user has access to all repositories.
    sig { params(user: User, org: Organization).returns(T.nilable(T.any(T::Array[NilClass], [T::Array[Integer], T::Boolean]))) }
    private_class_method def self.allowed_repo_ids_and_limit_exceeded(user:, org:)
      return [nil, nil] if can_manage_security_products?(user:, org:)

      allowed_repository_ids_by_feature_for_organization_members(user:, org:)[SecurityCenter::SecurityFeatures::CODE_SCANNING]
    end

    sig { params(user: User, org: Organization).returns(T::Boolean) }
    private_class_method def self.can_manage_security_products?(user:, org:)
      SecurityProduct::Permissions::OrgAuthz.new(org, actor: user).can_manage_security_products?
    end
  end
end
