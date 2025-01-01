# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class ReopeningService
    sig { params(campaign: SecurityCampaigns::SecurityCampaign, org: Organization, actor: User).void }
    def initialize(campaign:, org:, actor:)
      @campaign = campaign
      @org = org
      @actor = actor
    end

    sig { void }
    def call
      SecurityCampaigns::SecurityCampaign.transaction do
        # Reopen the campaign
        @campaign.update!(
          closed_at: nil,
          closure_open_count: nil,
          closure_closed_count: nil,
          closure_dismissed_count: nil,
          closure_autofix_supported_count: nil,
          closure_autofix_generated_count: nil,
          closure_autofix_accepted_count: nil,
        )

        # Ensure we're not exceeding the maximum number of campaigns
        if SecurityCampaigns::SecurityCampaign.lock.open.where(organization: @org).count > SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT
          raise ActiveRecord::Rollback, SecurityCampaigns::MAX_OPEN_CAMPAIGNS_REOPEN_ERROR_MESSAGE
        end
      rescue ActiveRecord::Deadlocked => e
        # Two concurrent transactions could look at the counts at the same time. If
        # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
        GitHub.dogstats.increment("security_campaigns.security_campaign_reopen", tags: ["kind:deadlock"])
        raise ActiveRecord::RecordNotSaved, SecurityCampaigns::CAMPAIGNS_CONCURRENT_REOPEN_MESSAGE
      end

      if @campaign.reload.closed?
        GitHub.dogstats.increment("security_campaigns.security_campaign_reopen", tags: ["kind:rollback"])
        raise ActiveRecord::RecordNotSaved, SecurityCampaigns::MAX_OPEN_CAMPAIGNS_REOPEN_ERROR_MESSAGE
      end

      GlobalInstrumenter.instrument("security_campaigns.security_campaign_reopen", {
        actor: @actor,
        security_campaign: @campaign,
      })
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, org: Organization, actor: User).void }
    def self.call(campaign:, org:, actor:)
      new(campaign:, org:, actor:).call
    end
  end
end
