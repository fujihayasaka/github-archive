# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class SendOverdueNotificationJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    sig { params(campaign_id: Integer).void }
    def perform(campaign_id:)
      return if GitHub.enterprise?
      return if GitHub.flipper[:security_campaigns_disable_send_overdue_notification_job].enabled?

      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: campaign_id)
      return if campaign.nil? || campaign.closed?
      # If the due date has changed and the campaign is now no longer overdue, we don't want to send a notification
      return if campaign.ends_at > Time.now + 2.hours

      # Find the open count for every repository in the campaign
      repo_numbers = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(campaign.security_campaign_alerts.to_a)
      alerts_response = GitHub::Turboscan.counts_by_repo_numbers({
        owner_ids: [campaign.organization_id],
        repo_numbers:,
      })

      raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

      data = alerts_response.data
      raise StandardError.new("No data when fetching alerts") if data.nil?

      # Only schedule notifications to be sent for repositories with open alerts
      repository_ids_with_open_alerts = data.repository_counts.filter_map do |repo_count|
        next unless repo_count.open_count > 0

        repo_count.repository_id
      end

      return if repository_ids_with_open_alerts.empty?

      repo_counts_by_repo = data.repository_counts.index_by(&:repository_id)

      # A notification requires an actor: we use the campaign manager. The actor will not be the sender of the
      # email, but it is required to be present and might be used for some email metadata.
      actor = campaign.safe_manager

      SecurityCampaignRepository.includes(:repository).where(security_campaign: campaign, repository_id: repository_ids_with_open_alerts).find_in_batches(batch_size: 10) do |campaign_repositories|
        campaign_repositories.each do |subject|
          Notifyd::NotifyPublisher.new.async_publish(
            actor_id: actor.id,
            subject_id: subject.id,
            subject_klass: subject.class.name,
            context: {
              actor_id: actor.id,
              actor_login: actor.display_login,
              operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Overdue.serialize,
              open_alerts_count: repo_counts_by_repo[subject.repository_id].open_count,
            }
          )
        end
      end
    end
  end
end
