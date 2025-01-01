# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This class contains a security campaign enriched with full alert data
  # from turboscan.
  class CampaignWithAlerts < CampaignBase
    extend T::Sig

    TurboscanAlert = Struct.new(:number, :rule, :message_text, :rule_severity, :security_severity, :tool, :most_recent_instance, :created_at, :is_fixed, :resolution, :repository_id)

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, turboscan_alerts: T::Array[TurboscanAlert], open_count: Integer, closed_count: Integer, next_cursor: T.nilable(String), prev_cursor: T.nilable(String), has_error: T::Boolean).void }
    def initialize(security_campaign:, turboscan_alerts:, open_count:, closed_count:, next_cursor:, prev_cursor:, has_error:)
      super(security_campaign, open_count, closed_count)
      @turboscan_alerts = turboscan_alerts
      @next_cursor = next_cursor
      @prev_cursor = prev_cursor
      @has_error = has_error
    end

    sig { returns(T::Array[TurboscanAlert]) }
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
        CodeScanning::RepoAlertTuple.new(repository_id: alert.repository_id, alert_number: alert.number)
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
      alert_query_service = alert_query_service(
        user: user,
        user_session: user_session,
        org: T.must(security_campaign.organization),
        repo: repo,
        query_string: query_string,
      )

      campaign_alerts = SecurityCampaigns::CampaignBase::load_campaign_alerts([security_campaign], repo:, strategy: alert_query_service.strategy, alert_numbers:)

      return CampaignWithAlerts.new(security_campaign:, turboscan_alerts: [], open_count: 0, closed_count: 0, next_cursor: nil, prev_cursor: nil, has_error: false) if campaign_alerts.empty?

      # Load alerts from turboscan
      load_turboscan_alerts(security_campaign, campaign_alerts, alert_query_service:, after_cursor:, before_cursor:)
    end


    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        campaign_alerts: T::Array[SecurityCampaignAlert],
        alert_query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns(CampaignWithAlerts)
    end
    def self.load_turboscan_alerts(security_campaign, campaign_alerts, alert_query_service:, after_cursor:, before_cursor:)
      tags = ["kind:turboscan_alerts_all_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        # Create repo, number pairs for all alerts
        repo_numbers = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(campaign_alerts)

        alert_results, has_error, alerts_response = code_scanning_alerts_for_alert_numbers(
          alert_query_service:, repo_numbers:,
          after_cursor:, before_cursor:,
        )

        turboscan_results = alerts_response&.data&.try(:results) || []
        open_count = T.let(alerts_response&.data&.try(:open_count) || 0, Integer)
        closed_count = T.let(alerts_response&.data&.try(:resolved_count) || 0, Integer)
        next_cursor = T.let(alerts_response&.data&.try(:next_cursor), T.nilable(String))
        prev_cursor = T.let(alerts_response&.data&.try(:prev_cursor), T.nilable(String))

        turboscan_alerts = alert_results.map do |repo_result|
          alert = repo_result.result
          next if alert.nil?
          TurboscanAlert.new(
            number: alert.number,
            rule: alert.rule,
            message_text: alert.message_text,
            rule_severity: alert.rule_severity,
            security_severity: alert.security_severity,
            tool: alert.tool,
            most_recent_instance: alert.most_recent_instance,
            created_at: alert.created_at,
            is_fixed: alert.is_fixed,
            resolution: alert.resolution,
            repository_id: repo_result.repository.id,
          )
        end.compact

        CampaignWithAlerts.new(
          security_campaign:,
          turboscan_alerts:,
          open_count:,
          closed_count:,
          next_cursor:,
          prev_cursor:,
          has_error:,
        )
      end
    end

    sig do
      params(
        repo_numbers: T::Array[Turboscan::Proto::RepoNumber],
        alert_query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns([T::Array[CodeScanning::AlertResult], T::Boolean, T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsByRepoResponse)])])
    end
    def self.code_scanning_alerts_for_alert_numbers(repo_numbers:, alert_query_service:, after_cursor:, before_cursor:)
      tags = ["kind:turboscan_alerts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        alert_results, _, has_error, response = alert_query_service.alerts_by_repo_with_response(per_page: page_size, before_cursor:, after_cursor:, repo_numbers:,)

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
      ).returns(CodeScanning::AlertQueryService)
    end
    private_class_method def self.alert_query_service(user:, user_session:, org:, repo:, query_string:)
      if repo.present?
        CodeScanning::AlertQueryService.for_repository(
          user: user,
          user_session: user_session,
          repository: repo,
          query: query_string,
          visibility: SecurityCampaigns::REPOSITORY_VISIBILITIES,
        )
      else
        allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded(user:, org:)

        CodeScanning::AlertQueryService.for_organization(
          user: user,
          user_session: user_session,
          organization: org,
          allowed_repository_ids: allowed_repo_ids,
          query: query_string,
          visibility: SecurityCampaigns::REPOSITORY_VISIBILITIES,
        )
      end
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
