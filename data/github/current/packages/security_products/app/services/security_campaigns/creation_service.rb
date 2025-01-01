# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class CreationService
    sig do
      params(
        opening_details: CampaignOpeningDetails,
        actor: User,
      ).void
    end
    def initialize(opening_details:, actor:)
      @opening_details = opening_details
      @actor = actor
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      campaign = SecurityCampaigns::SecurityCampaign.from_opening_details(@opening_details, Time.zone.now)

      ActiveRecord::Base.connected_to(role: :writing) do
        SecurityCampaign.transaction do
          # Create a new security campaign
          campaign.save!

          # Ensure we're not exceeding the maximum number of campaigns
          # NOTE: the lock is important otherwise the transaction does not guarantee that the count is accurate
          if SecurityCampaign.lock.open.where(organization_id: campaign.organization_id).count > MAX_OPEN_CAMPAIGNS_COUNT
            raise ActiveRecord::Rollback, MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE
          end
        rescue ActiveRecord::Deadlocked => e
          # Two concurrent transactions could block at the counts at the same time, if
          # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
          GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:deadlock"])
          raise ActiveRecord::RecordNotSaved, OPEN_CAMPAIGNS_CONCURRENT_CREATION_MESSAGE
        end

        if !campaign.persisted?
          GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:rollback"])
          raise ActiveRecord::RecordNotSaved, MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE
        end
        GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:success"])
      end

      # This should happen after the transaction is committed
      OpeningService.call(campaign:, opening_details: @opening_details, actor: @actor)

      campaign
    end

    # opening_details - Details around the opening of the security campaign
    # actor - The user that created the security campaign
    sig do
      params(
        opening_details: CampaignOpeningDetails,
        actor: User,
      ).returns(SecurityCampaigns::SecurityCampaign)
    end
    def self.call(opening_details:, actor:)
      new(opening_details:, actor:).call
    end
  end
end
