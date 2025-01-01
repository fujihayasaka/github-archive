# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class CreationService
    sig { params(campaign: SecurityCampaigns::SecurityCampaign, logical_alert_info: T::Hash[Integer, T::Array[Turboscan::Proto::Result]], actor: User, query_string: String).void }
    def initialize(campaign:, logical_alert_info:, actor:, query_string:)
      @campaign = campaign
      @logical_alert_info = logical_alert_info
      @actor = actor
      @query_string = query_string
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      ActiveRecord::Base.connected_to(role: :writing) do
        SecurityCampaign.transaction do
          # Create a new security campaign
          @campaign.save!

          # Ensure we're not exceeding the maximum number of campaigns
          # NOTE: the lock is important otherwise the transaction does not guarantee that the count is accurate
          if SecurityCampaign.lock.open.where(organization_id: @campaign.organization_id).count > MAX_CAMPAIGNS_COUNT
            raise ActiveRecord::Rollback, MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE
          end
        rescue ActiveRecord::Deadlocked => e
          # Two concurrent transactions could block at the counts at the same time, if
          # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
          GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:deadlock"])
          raise ActiveRecord::RecordNotSaved, CAMPAIGNS_CONCURRENT_CREATION_MESSAGE
        end

        if !@campaign.persisted?
          GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:rollback"])
          raise ActiveRecord::RecordNotSaved, MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE
        end
        GitHub.dogstats.increment("security_campaigns.creation_event", tags: ["kind:success"])

        # Create a new security campaign alert for each logical alert number

        SecurityCampaigns::SecurityCampaignAlert.insert_all(
          @logical_alert_info.map do |repo_id, logical_alerts|
            logical_alerts.map do |logical_alert|
              {
                security_campaign_id: @campaign.id,
                logical_alert_number: logical_alert.number,
                repository_id: repo_id
              }
            end
          end.flatten
        )

        unless T.must(@campaign.organization).feature_enabled?(:security_campaigns_one_email_per_campaign)
          SecurityCampaigns::SecurityCampaignRepository.insert_all(
            @logical_alert_info.keys.map do |repo_id|
              {
                security_campaign_id: @campaign.id,
                repository_id: repo_id,
              }
            end
          )
        end
      end

      # This happens before notifications are sent
      GlobalInstrumenter.instrument("security_campaigns.security_campaign_create", {
        actor: @actor,
        query: @query_string,
        repo_count: @logical_alert_info.keys.size,
        alert_count: @logical_alert_info.values.flat_map(&:uniq).size,
        security_campaign: @campaign,
      })

      # This should happen after the transaction is committed
      if T.must(@campaign.organization).feature_enabled?(:security_campaigns_one_email_per_campaign)
        SecurityCampaigns::SendCreationNotificationJob.perform_later(
          actor_id: T.must(@actor.id),
          campaign_id: T.must(@campaign.id),
          repo_ids: @logical_alert_info.keys
        )
      else
        GlobalInstrumenter.instrument("security_campaigns.security_campaign_repository_notification", {
          actor: @actor,
          security_campaign: @campaign,
          repository_ids: @logical_alert_info.keys.to_set,
        })
      end

      logical_alert_info = []
      @logical_alert_info.each do |repo_id, repo_alerts|
        logical_alert_info << { repo_id: repo_id, alerts: repo_alerts.map { |alert| { alert_number: alert.number, tool_name: T.must(alert.tool).name } } }
      end
      SecurityCampaigns::GenerateAutofixesJob.perform_later(campaign_id: T.must(@campaign.id), logical_alert_info:)

      @campaign
    end

    # campaign - The security campaign to create
    # logical_alert_info - Hash of {repo_id: [logical_alert_number1, logical_alert_number2, ..]} entries
    # actor - The user that created the security campaign
    # query_string - The query string used to create the security campaign
    sig { params(campaign: SecurityCampaigns::SecurityCampaign, logical_alert_info: T::Hash[Integer, T::Array[Turboscan::Proto::Result]], actor: User, query_string: String).returns(SecurityCampaigns::SecurityCampaign) }
    def self.call(campaign:, logical_alert_info:, actor:, query_string:)
      new(campaign:, logical_alert_info:, actor:, query_string:).call
    end
  end
end
