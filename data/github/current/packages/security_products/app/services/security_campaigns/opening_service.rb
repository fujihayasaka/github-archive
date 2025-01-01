# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class OpeningService
    sig do
      params(
        campaign: SecurityCampaign,
        opening_details: CampaignOpeningDetails,
        actor: User,
      ).void
    end
    def initialize(campaign:, opening_details:, actor:)
      @campaign = campaign
      @opening_details = opening_details
      @actor = actor
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      # Create a new security campaign alert for each logical alert number
      create_security_campaign_alerts(@campaign)

      # This happens before notifications are sent
      GlobalInstrumenter.instrument("security_campaigns.security_campaign_create", {
        actor: @actor,
        query: @opening_details.query_string,
        repo_count: @opening_details.alerts.keys.size,
        alert_count: @opening_details.alerts.values.flat_map(&:uniq).size,
        security_campaign: @campaign,
        source_campaign_id: @opening_details.source_campaign_id,
      })

      SecurityCampaigns::SendCreationNotificationJob.perform_later(
        actor_id: @actor.id,
        campaign_id: @campaign.id,
        repo_ids: @opening_details.alerts.keys
      )

      logical_alert_info = []
      @opening_details.alerts.each do |repo_id, repo_alerts|
        logical_alert_info << { repo_id: repo_id, alerts: repo_alerts.map { |alert| { alert_number: alert.number, tool_name: T.must(alert.tool).name } } }
      end
      generate_autofix_pull_requests = @opening_details.generate_autofix_pull_requests && SecurityCampaigns.autofix_pr_creation_enabled?(T.must(@campaign.organization))
      SecurityCampaigns::GenerateAutofixesJob.perform_later(campaign_id: @campaign.id, logical_alert_info:, generate_autofix_pull_requests:)

      SecurityCampaigns::CreateIssuesJob.perform_later(campaign_id: @campaign.id, repository_ids: @opening_details.alerts.keys) if @opening_details.generate_issues

      @campaign
    end

    # campaign - The security campaign to open
    # opening_details - Details around the opening of the security campaign
    # actor - The user that created the security campaign
    sig do
      params(
        campaign: SecurityCampaign,
        opening_details: CampaignOpeningDetails,
        actor: User,
      ).returns(SecurityCampaigns::SecurityCampaign)
    end
    def self.call(campaign:, opening_details:, actor:)
      new(campaign:, opening_details:, actor:).call
    end

    private

    sig { params(campaign: SecurityCampaign).void }
    def create_security_campaign_alerts(campaign)
      tags = ["kind:turboscan_create_security_campaign_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.create_security_campaign_alerts", tags: tags) do
        repo_numbers = @opening_details.alerts.flat_map do |repository_id, logical_alerts|
          logical_alerts.map do |logical_alert|
            {
              number: logical_alert.number,
              repository_id:
            }
          end
        end

        response = GitHub::Turboscan.create_security_campaign_alerts(security_campaign_id: campaign.id, repo_numbers:)
        raise TurboscanError if response&.data.nil? || response&.error.present?
      end
    end
  end
end
