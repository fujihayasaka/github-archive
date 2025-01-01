# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class OpeningService
    sig do
      params(
        campaign: SecurityCampaign,
        opening_details: CampaignOpeningDetails,
        actor: User,
        draft: T::Boolean
      ).void
    end
    def initialize(campaign:, opening_details:, actor:, draft:)
      @campaign = campaign
      @opening_details = opening_details
      @actor = actor
      @draft = draft
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    def call
      # Create a new security campaign alert for each logical alert number
      create_security_campaign_alerts(@campaign)

      # This happens before notifications are sent
      if @draft
        GlobalInstrumenter.instrument("security_campaigns.security_campaign_publish_draft", {
          actor: @actor,
          security_campaign: @campaign,
          source_campaign_id: @opening_details.source_campaign_id,
        })
      else
        GlobalInstrumenter.instrument("security_campaigns.security_campaign_create", {
          actor: @actor,
          repo_count: @opening_details.alerts.keys.size,
          alert_count: @opening_details.alerts.values.flat_map(&:uniq).size,
          security_campaign: @campaign,
          source_campaign_id: @opening_details.source_campaign_id,
        })
      end

      SecurityCampaigns::SendCreationNotificationJob.perform_later(
        campaign_id: @campaign.id,
        repo_ids: @opening_details.alerts.keys
      )

      logical_alert_info = []
      @opening_details.alerts.each do |repo_id, repo_alerts|
        logical_alert_info << { repo_id: repo_id, alerts: repo_alerts.map { |alert| { alert_number: alert.number, tool_name: T.must(alert.tool).name } } }
      end
      SecurityCampaigns::GenerateAutofixesJob.perform_later(campaign_id: @campaign.id, logical_alert_info:)

      SecurityCampaigns::CreateIssuesJob.perform_later(campaign_id: @campaign.id, repository_ids: @opening_details.alerts.keys) if @opening_details.generate_issues

      @campaign
    end

    # campaign - The security campaign to open
    # opening_details - Details around the opening of the security campaign
    # actor - The user that created the security campaign
    # draft - A boolean indicating whether the security campaign was in draft
    sig do
      params(
        campaign: SecurityCampaign,
        opening_details: CampaignOpeningDetails,
        actor: User,
        draft: T::Boolean
      ).returns(SecurityCampaigns::SecurityCampaign)
    end
    def self.call(campaign:, opening_details:, actor:, draft:)
      new(campaign:, opening_details:, actor:, draft:).call
    end

    private

    sig { params(campaign: SecurityCampaign).void }
    def create_security_campaign_alerts(campaign)
      case campaign.alert_type
      when "code_scanning"
        create_code_scanning_campaign_alerts(campaign)
      when "secret_scanning"
        create_secret_scanning_campaign_alerts(campaign)
      end
    end

    sig { params(campaign: SecurityCampaign).void }
    def create_code_scanning_campaign_alerts(campaign)
      return unless campaign.alert_type == "code_scanning"
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

    sig { params(campaign: SecurityCampaign).void }
    def create_secret_scanning_campaign_alerts(campaign)
      return unless campaign.alert_type == "secret_scanning"
      tags = ["kind:tss_create_security_campaign_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.create_security_campaign_alerts", tags: tags) do
        repo_numbers = @opening_details.secret_scanning_alerts.flat_map do |repository_id, alerts|
          alerts.map do |alert|
            GitHub::Proto::SecretScanning::Api::V2::TokenNumber.new(
              number: alert.number,
              repository_id:
            )
          end
        end

        response = GitHub::TokenScanning::Service::Client.new(@actor).set_campaign_assignments(GitHub::Proto::SecretScanning::Api::V2::CampaignAssignmentsRequest.new(
          assignments: repo_numbers,
          campaign_id: campaign.id,
          updated_by_id: @actor.id,
        ))
        raise TokenScanningServiceError if response&.data.nil? || response&.error.present?
      end
    end
  end
end
