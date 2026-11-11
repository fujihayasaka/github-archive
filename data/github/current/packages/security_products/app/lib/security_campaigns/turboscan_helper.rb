# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This class contains helper methods for accessing Turboscan in campaigns code.
  class TurboscanHelper
    sig { params(campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Turboscan::Proto::RepoResult]) }
    def self.alerts_by(campaign:)
      turboscan_alerts = T.let([], T::Array[Turboscan::Proto::RepoResult])
      after_cursor = T.let(nil, T.nilable(String))

      while turboscan_alerts.size < SecurityCampaigns::MAX_ALERTS_COUNT do
        alerts_response = GitHub::Turboscan.alerts_by_repo(
          owner_ids: [campaign.organization_id],
          security_campaign_ids: [campaign.id],
          limit: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
          after_cursor:,
        )

        raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

        alerts_response = alerts_response.data

        page_turboscan_alerts = alerts_response.results.to_a
        turboscan_alerts += page_turboscan_alerts

        after_cursor = alerts_response.next_cursor

        if after_cursor.blank?
          # If we receive an empty next cursor, there are no more results on the next pages.
          break
        end
      end

      turboscan_alerts
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Turboscan::Proto::RepoSuggestedFixState]) }
    def self.suggested_fix_states_by(campaign:)
      suggested_fix_states = T.let([], T::Array[Turboscan::Proto::RepoSuggestedFixState])
      after_cursor = T.let(nil, T.nilable(String))

      while true do
        suggested_fix_states_response = GitHub::Turboscan::SuggestedFixes.suggested_fix_states_for_org(
          owner_ids: [campaign.organization_id],
          filter: {
            security_campaign_ids: [campaign.id]
          },
          limit: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
          after_cursor:,
        )

        raise StandardError.new(suggested_fix_states_response&.error&.msg || "No response when fetching suggested fix states") if suggested_fix_states_response.nil? || suggested_fix_states_response.error.present?

        suggested_fix_states_response = suggested_fix_states_response.data

        page_suggested_fix_states = suggested_fix_states_response.suggested_fix_states.to_a
        suggested_fix_states += page_suggested_fix_states

        after_cursor = suggested_fix_states_response.next_cursor

        if after_cursor.blank?
          # If we receive an empty next cursor, there are no more results on the next pages.
          break
        end
      end

      suggested_fix_states
    end

    sig { params(repo_numbers: T::Array[Turboscan::Proto::RepoNumber]).returns(T::Array[Turboscan::Proto::AlertLink]) }
    def self.alert_links_for(repo_numbers:)
      return [] if repo_numbers.empty?

      alert_links = T.let([], T::Array[Turboscan::Proto::AlertLink])

      repo_numbers.each_slice(SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE) do |repo_numbers_slice|
        alert_link_response = GitHub::Turboscan::get_links_for_alerts(
          repos_and_alerts: repo_numbers_slice,
        )

        raise StandardError.new(alert_link_response&.error&.msg || "No response when fetching alert links") if alert_link_response.nil? || alert_link_response.error.present?

        alert_link_response = alert_link_response.data

        page_alert_link_response = alert_link_response.links.to_a
        alert_links += page_alert_link_response
      end

      alert_links
    end
  end
end
