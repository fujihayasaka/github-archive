# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class ClosureService
    sig { params(campaign: SecurityCampaigns::SecurityCampaign, actor: User, org: Organization).void }
    def initialize(campaign:, actor:, org:)
      @campaign = campaign
      @actor = actor
      @org = org
    end

    sig { void }
    def call
      # Get stats for the campaign
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: @actor,
        user_session: nil,
        organization: T.must(@campaign.organization),
        security_campaign_ids: [@campaign.id],
      )
      campaign_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [@campaign], query_service:).first

      raise StandardError, "Could not get counts for campaign #{@campaign.id}" if campaign_with_counts.nil?

      # Update campaign
      @campaign.update!(
        closed_at: Time.now.utc,
        closure_open_count: campaign_with_counts.open_count,
        closure_closed_count: campaign_with_counts.closed_count,
        closure_dismissed_count: campaign_with_counts.dismissed_count,
        closure_autofix_supported_count: campaign_with_counts.autofix_supported_count,
        closure_autofix_generated_count: campaign_with_counts.autofix_generated_count,
        closure_autofix_accepted_count: campaign_with_counts.autofix_accepted_count,
      )

      if SecurityCampaigns.issue_creation_enabled?(@org)
        PostCampaignClosedCommentsJob.perform_later(campaign_id: @campaign.id, actor_id: @actor.id)
      end

      GlobalInstrumenter.instrument("security_campaigns.security_campaign_close", {
        actor: @actor,
        security_campaign: @campaign,
      })
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, actor: User, org: Organization).void }
    def self.call(campaign:, actor:, org:)
      new(campaign:, actor:, org:).call
    end
  end
end
