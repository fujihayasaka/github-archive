# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class DeletionService
    sig { params(campaign: SecurityCampaigns::SecurityCampaign, actor: User).void }
    def initialize(campaign:, actor:)
      @campaign = campaign
      @actor = actor
    end

    sig { void }
    def call
      # Any delete calls in this class should be throttled if they are moved to a background job.
      # However, we can't throttle in a web request because that might result in timeouts.

      tags = ["kind:turboscan_delete_security_campaign_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.delete_security_campaign_alerts", tags: tags) do
        GitHub::Turboscan.delete_security_campaign_alerts(security_campaign_id:  @campaign.id)
      end

      # Posting issue comments is probably too slow for a web request and also not time critical,
      # but we need to fetch the issue IDs before we delete the campaign and pass that info to the job.
      # The job can't rely on the campaign existing.
      if SecurityCampaigns.issue_creation_enabled?(T.must(@campaign.organization))
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_later(
          deleted_campaign_id: @campaign.id,
          org_id: @campaign.organization_id,
          issue_ids: @campaign.security_campaign_issues.includes(:issue).filter_map(&:issue_following_transfers).map(&:id),
          actor_id: @actor.id,
          contact_link_present: @campaign.contact_link.present?,
        )
      end

      @campaign.destroy!

      GlobalInstrumenter.instrument("security_campaigns.security_campaign_delete", {
        actor: @actor,
        security_campaign: @campaign,
      })
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, actor: User).void }
    def self.call(campaign:, actor:)
      new(campaign:, actor:).call
    end
  end
end
