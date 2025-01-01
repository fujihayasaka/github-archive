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
      # These delete calls should be throttled if they are moved to a background job. However, we can't throttle in a
      # web request because that might result in timeouts.
      SecurityCampaigns::SecurityCampaignRepository.where(security_campaign_id: @campaign.id).in_batches(of: 10) do |batch|
        batch.delete_all
      end
      SecurityCampaigns::SecurityCampaignAlert.where(security_campaign_id: @campaign.id).in_batches(of: 10) do |batch|
        batch.delete_all
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
