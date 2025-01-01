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
    # query_service is the CodeScanning::AlertQueryService that will be used to load alerts
    # from turboscan. It should be created with the security_campaign_ids set to the id of the security campaign.
    # After and before are cursors to load the next/previous page of alerts. Only 1 of them should be specified.
    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns(CampaignWithAlerts)
    end
    def self.load_campaign(security_campaign:, query_service:, after_cursor: nil, before_cursor: nil)
      tags = ["kind:turboscan_alerts_all_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        alert_results, has_error, alerts_response = code_scanning_alerts_for_alert_numbers(
          query_service:,
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
        query_service: CodeScanning::AlertQueryService,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
      ).returns([T::Array[CodeScanning::AlertResult], T::Boolean, T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsByRepoResponse)])])
    end
    def self.code_scanning_alerts_for_alert_numbers(query_service:, after_cursor:, before_cursor:)
      tags = ["kind:turboscan_alerts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        alert_results, _, has_error, response = query_service.alerts_by_repo_with_response(per_page: page_size, before_cursor:, after_cursor:)

        [alert_results, has_error, response]
      end
    end

    # Returns the page size to use for pagination
    sig { returns(Integer) }
    def self.page_size
      25
    end
  end
end
