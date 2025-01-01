# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class PublishingService
    sig do
      params(
        campaign: SecurityCampaigns::SecurityCampaign,
        opening_details: CampaignOpeningDetails,
        actor: User
      ).void
    end
    def initialize(campaign:, opening_details:, actor:)
      @campaign = campaign
      @opening_details = opening_details
      @actor = actor
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      SecurityCampaigns::SecurityCampaign.transaction do
        @campaign.update!(
          published_at: Time.now.utc,
          name: @opening_details.name,
          description: @opening_details.description,
          contact_link: @opening_details.contact_link,
          user_manager_users: @opening_details.managers,
          team_manager_teams: @opening_details.team_managers,
          ends_at: @opening_details.ends_at,
          creation_query: @opening_details.query_string
        )

        # Ensure we're not exceeding the maximum number of open campaigns
        if SecurityCampaigns::SecurityCampaign.lock.open.where(organization: @campaign.organization_id).count > SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT
          raise ActiveRecord::Rollback, SecurityCampaigns::MAX_OPEN_CAMPAIGNS_PUBLISH_ERROR_MESSAGE
        end
      rescue ActiveRecord::Deadlocked => e
        # Two concurrent transactions could look at the counts at the same time. If
        # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
        GitHub.dogstats.increment("security_campaigns.security_campaign_publish", tags: ["kind:deadlock"])
        raise ActiveRecord::RecordNotSaved, SecurityCampaigns::CAMPAIGNS_CONCURRENT_PUBLISH_MESSAGE
      end

      if @campaign.reload.draft?
        GitHub.dogstats.increment("security_campaigns.security_campaign_publish", tags: ["kind:rollback"])
        raise ActiveRecord::RecordNotSaved, SecurityCampaigns::MAX_OPEN_CAMPAIGNS_PUBLISH_ERROR_MESSAGE
      end

      OpeningService.call(
        campaign: @campaign,
        opening_details: @opening_details,
        actor: @actor)

      @campaign
    end

    # campaign - The security campaign to create
    # actor - The user that created the security campaign
    # opening_details - Details around the opening of the security campaign
    sig do
      params(
        campaign: SecurityCampaigns::SecurityCampaign,
        opening_details: SecurityCampaigns::CampaignOpeningDetails,
        actor: User
      ).returns(SecurityCampaigns::SecurityCampaign)
    end
    def self.call(campaign:, opening_details:, actor:)
      new(campaign:, opening_details:, actor:).call
    end
  end
end
