# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class DraftCreationService
    sig { params(campaign: SecurityCampaigns::SecurityCampaign).void }
    def initialize(campaign:)
      @campaign = campaign
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      ActiveRecord::Base.connected_to(role: :writing) do
        SecurityCampaign.transaction do
          # Create a new security campaign
          @campaign.save!

          # Ensure we're not exceeding the maximum number of draft campaigns
          # NOTE: the lock is important otherwise the transaction does not guarantee that the count is accurate
          if SecurityCampaign.lock.draft.where(organization_id: @campaign.organization_id).count > MAX_DRAFT_CAMPAIGNS_COUNT
            raise ActiveRecord::Rollback, MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE
          end
        rescue ActiveRecord::Deadlocked => e
          # Two concurrent transactions could block at the counts at the same time, if
          # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
          GitHub.dogstats.increment("security_campaigns.draft_creation_event", tags: ["kind:deadlock"])
          raise ActiveRecord::RecordNotSaved, DRAFT_CAMPAIGNS_CONCURRENT_CREATION_MESSAGE
        end

        if !@campaign.persisted?
          GitHub.dogstats.increment("security_campaigns.draft_creation_event", tags: ["kind:rollback"])
          raise ActiveRecord::RecordNotSaved, MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE
        end
        GitHub.dogstats.increment("security_campaigns.draft_creation_event", tags: ["kind:success"])
      end

      @campaign
    end

    # campaign - The security campaign to create
    sig { params(campaign: SecurityCampaigns::SecurityCampaign).returns(SecurityCampaigns::SecurityCampaign) }
    def self.call(campaign:)
      new(campaign:).call
    end
  end
end
