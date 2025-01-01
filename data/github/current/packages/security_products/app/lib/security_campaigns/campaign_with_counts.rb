# typed: strict
# frozen_string_literal: true

# This class contains several security campaigns enriched with information about alert counts.
module SecurityCampaigns
  class CampaignWithCounts < CampaignBase
    sig { returns(Integer) }
    def dismissed_count
      @counts.dismissed_count
    end

    sig { returns(Integer) }
    def autofix_supported_count
      @counts.autofix_supported_count
    end

    sig { returns(Integer) }
    def autofix_generated_count
      @counts.autofix_generated_count
    end

    sig { returns(Integer) }
    def autofix_accepted_count
      @counts.autofix_accepted_count
    end

    sig { params(security_campaign: SecurityCampaign, counts: DetailedCampaignCounts).void }
    def initialize(security_campaign, counts)
      super(security_campaign, counts)
      @counts = counts
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaign],
        user: User,
        query_service: T.nilable(CodeScanning::AlertQueryService),
        repo: T.nilable(Repository),
      ).returns(T::Array[CampaignWithCounts])
    end
    def self.load(security_campaigns:, user:, query_service: nil, repo: nil)
      return [] if security_campaigns.empty?

      org_campaigns_with_counts(security_campaigns:, user:, query_service:, repo:)
    end

    ## Used to filter out campaigns that have no alerts on given repo
    ## We use the counts from the Turboscan API to determine if a campaign has alerts
    sig { params(security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign], repo: Repository, user: User).returns(T::Array[CampaignWithCounts]) }
    def self.for_repo_with_alerts(security_campaigns:, repo:, user:)
      campaigns_with_counts = org_campaigns_with_counts(security_campaigns:, repo:, user:)

      campaigns_with_counts.filter do |campaign_with_counts|
        campaign_with_counts.open_count > 0 || campaign_with_counts.closed_count > 0
      end
    end

    ## Used to filter out campaigns that do not have the specific alert number and repo included.
    ## Note that the full repo-level campaign (with its original count is returned).
    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: Repository,
        alert_number: Integer,
        user: User,
      ).returns(T::Array[CampaignWithCounts])
    end
    def self.for_repo_and_alert_number(security_campaigns:, repo:, alert_number:, user:)
      # First fetch the counts for the specific alert number
      campaigns_for_alert = org_campaigns_with_counts(
        security_campaigns:,
        repo:,
        user:,
        repo_numbers: [
          Turboscan::Proto::RepoNumber.new(
            repository_id: repo.id,
            number: alert_number,
          )
        ]
      )
      # The relevant campaigns are the ones that contain the alert.
      security_campaigns_for_alert = security_campaigns.select do |campaign|
        campaigns_for_alert.any? { |campaign_with_counts| campaign_with_counts.id == campaign.id && campaign_with_counts.total_count > 0  }
      end
      # Now fetch the total counts for those campaigns
      campaigns_with_counts = org_campaigns_with_counts(
        security_campaigns: security_campaigns_for_alert,
        repo:,
        user:
      )
      # There should not be anything to filter - expect if they campaign changed between the two calls to turboscan.
      # If it did we just filter it here.
      campaigns_with_counts.filter do |campaign_with_counts|
        campaign_with_counts.total_count > 0
      end
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        user: User,
        query_service:  T.nilable(CodeScanning::AlertQueryService),
        repo: T.nilable(Repository),
        repo_numbers: T.nilable(T::Array[Turboscan::Proto::RepoNumber]),
      ).returns(T::Array[CampaignWithCounts])
    end
    private_class_method def self.org_campaigns_with_counts(security_campaigns:, user:, query_service: nil, repo: nil, repo_numbers: nil)
      ## If there are no security campaigns, we return an empty array
      return [] if security_campaigns.empty?

      ## Making sure all campaigns belong to same org
      org_ids = security_campaigns.map(&:organization_id).uniq
      if org_ids.size > 1
        GitHub.logger.info("Security campaigns from different orgs",
          "code.function" => "org_campaigns_with_counts",
          "gh.security_campaign_ids" => security_campaigns.map(&:id),
          "gh.security_campaigns_org_ids" => org_ids
        )
        return security_campaigns.map { |campaign| CampaignWithCounts.new(campaign, DetailedCampaignCounts.empty) }
      end

      organization = T.must(T.must(security_campaigns.first).organization)
      query_service ||= CodeScanning::AlertQueryService.for_organization(
        user:,
        user_session: nil,
        organization:,
        security_campaign_ids: security_campaigns.filter_map(&:id),
        allowed_repository_ids: repo ? [repo.id] : nil,
        repo_numbers:
      )
      alerts_response = query_service.counts_by_campaigns

      if alerts_response.present? && alerts_response.data.present?
        security_campaigns.map do |campaign|
          campaign_count = T.must(alerts_response.data).campaign_counts.find do |campaign_count|
            campaign_count.campaign_id == campaign.id
          end
          next CampaignWithCounts.new(campaign, DetailedCampaignCounts.empty) unless campaign_count.present?

          counts = DetailedCampaignCounts.new(
            open_count: campaign_count.open_count,
            closed_count: campaign_count.closed_count,
            open_with_links_count: campaign_count.open_with_links_count,
            dismissed_count: campaign_count.dismissed_count,
            autofix_supported_count: campaign_count.autofix_supported_count,
            autofix_generated_count: campaign_count.autofix_generated_count,
            autofix_accepted_count: campaign_count.autofix_accepted_count,
          )
          CampaignWithCounts.new(campaign, counts)
        end
      else
        security_campaigns.map { |campaign| CampaignWithCounts.new(campaign, DetailedCampaignCounts.empty) }
      end
    end
  end
end
