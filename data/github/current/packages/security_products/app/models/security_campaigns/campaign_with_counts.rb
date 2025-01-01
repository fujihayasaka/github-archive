# typed: strict
# frozen_string_literal: true

# This class contains several security campaigns enriched with information about alert counts.
module SecurityCampaigns
  class CampaignWithCounts < CampaignBase

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, open_count: Integer, closed_count: Integer, open_with_links_count: Integer).void }
    def initialize(security_campaign, open_count, closed_count, open_with_links_count)
      super
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        user: User,
        query_service: T.nilable(CodeScanning::AlertQueryService),
        repo: T.nilable(Repository),
      ).returns(T::Array[CampaignWithCounts])
    end
    def self.load(security_campaigns:, user:, query_service: nil, repo: nil)
      return [] if security_campaigns.empty?

      ## This is related to new data model spike for security campaigns
      ## We need to add more filters used in load_campaign_alerts to the alert query service
      return campaigns_with_count(security_campaigns:, repo:) if user.feature_enabled?(:security_campaigns_read_without_alerts_limit)

      campaign_alerts = SecurityCampaigns::CampaignBase::load_campaign_alerts(security_campaigns, repo:, strategy: query_service&.strategy, alert_numbers: nil)

      # Split campaign alerts by campaign and fetch the count for each campaign.
      campaign_alerts_by_campaign = campaign_alerts.group_by(&:security_campaign_id)

      # Collect org ids
      org_ids = security_campaigns.map(&:organization_id).uniq

      # Find count for each campaign

      tags = ["kind:turboscan_counts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        security_campaigns.map do |campaign|
          campaign_id = campaign.id
          next if campaign_id.nil?
          campaign_alerts_for_campaign = campaign_alerts_by_campaign[campaign_id] || []
          next unless campaign_alerts_for_campaign.size > 0

          repo_numbers_for_campaign = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(campaign_alerts_for_campaign)

          alerts_response = GitHub::Turboscan.counts_by_repo_numbers({
              owner_ids: org_ids,
              repo_numbers: repo_numbers_for_campaign,
            }
          )

          open_count, closed_count, open_with_links_count = 0, 0, 0
          if alerts_response.present? && alerts_response.data.present?
            open_count = T.must(alerts_response.data).open_count
            closed_count = T.must(alerts_response.data).closed_count
            open_with_links_count = T.must(alerts_response.data).open_with_links_count
          end
          CampaignWithCounts.new(campaign, open_count, closed_count, open_with_links_count)
        end.compact
      end
    end

    ## Used to filter out campaigns that have no alerts on given repo
    ## We use the counts from the Turboscan API to determine if a campaign has alerts
    sig { params(security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign], repo: Repository).returns(T::Array[CampaignWithCounts]) }
    def self.for_repo_with_alerts(security_campaigns:, repo:)
      campaigns_with_counts = self.campaigns_with_count(security_campaigns:, repo:)

      campaigns_with_counts.filter do |campaign_with_counts|
        campaign_with_counts.open_count > 0 || campaign_with_counts.closed_count > 0
      end
    end

    ## Used to filter given alerts by an alert number
    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: Repository,
        alert_number: Integer,
      ).returns(T::Array[CampaignWithCounts])
    end
    def self.for_repo_and_alert_number(security_campaigns:, repo:, alert_number:)
      campaigns_with_counts = campaigns_with_count(
        security_campaigns:,
        repo:,
        repo_numbers: [
          Turboscan::Proto::RepoNumber.new(
            repository_id: repo.id,
            number: alert_number,
          )
        ]
      )
      campaigns_with_counts.filter do |campaign_with_counts|
        campaign_with_counts.open_count > 0 || campaign_with_counts.closed_count > 0
      end
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: T.nilable(Repository),
        repo_numbers: T.nilable(T::Array[Turboscan::Proto::RepoNumber]),
      ).returns(T::Array[CampaignWithCounts])
    end
    private_class_method def self.campaigns_with_count(security_campaigns:, repo: nil, repo_numbers: nil)
      org_ids = security_campaigns.map(&:organization_id).uniq
      filter = repo_numbers.nil? ? nil : { repo_numbers: }
      alerts_response = GitHub::Turboscan.counts_by_campaigns({
          owner_ids: org_ids,
          security_campaign_ids: security_campaigns.map(&:id),
          repository_ids: repo.nil? ? nil : [repo.id],
          filter:
        }.compact
      )
      if alerts_response.present? && alerts_response.data.present?
        security_campaigns.map do |campaign|
          campaign_count = T.must(alerts_response.data).campaign_counts.find do |campaign_count|
            campaign_count.campaign_id == campaign.id
          end
          next CampaignWithCounts.new(campaign, 0, 0, 0) unless campaign_count.present?

          open_count = campaign_count.open_count
          closed_count = campaign_count.closed_count
          open_with_links_count = campaign_count.open_with_links_count
          CampaignWithCounts.new(campaign, open_count, closed_count, open_with_links_count)
        end
      else
        security_campaigns.map { |campaign| CampaignWithCounts.new(campaign, 0, 0, 0) }
      end
    end
  end
end
