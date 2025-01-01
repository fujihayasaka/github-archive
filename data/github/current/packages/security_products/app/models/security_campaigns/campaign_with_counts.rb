# typed: strict
# frozen_string_literal: true

# This class contains several security campaigns enriched with information about alert counts.
module SecurityCampaigns
  class CampaignWithCounts < CampaignBase
    extend T::Sig

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, open_count: Integer, closed_count: Integer).void }
    def initialize(security_campaign, open_count, closed_count)
      super
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: T.nilable(Repository)
      ).returns(T::Array[CampaignWithCounts])
    end
    def self.load(security_campaigns, repo: nil)
      campaign_alerts = SecurityCampaigns::CampaignBase::load_campaign_alerts(security_campaigns, repo:, strategy: nil, alert_numbers: nil)

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

          open_count, closed_count = 0, 0
          if alerts_response.present? && alerts_response.data.present?
            open_count = T.must(alerts_response.data).open_count
            closed_count = T.must(alerts_response.data).closed_count
          end
          CampaignWithCounts.new(campaign, open_count, closed_count)
        end.compact
      end
    end
  end
end
