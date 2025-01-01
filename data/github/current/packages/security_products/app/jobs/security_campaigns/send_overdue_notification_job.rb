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

      campaign = SecurityCampaigns::SecurityCampaign.open.find_by(id: campaign_id)
      return if campaign.nil?
      # If the due date has changed and the campaign is now no longer overdue, we don't want to send a notification
      return if campaign.ends_at > Time.now + 2.hours

      organization = campaign.organization
      return if organization.nil?

      # Find the open count for every repository in the campaign
      alerts_response = GitHub::Turboscan.counts_by_repo({
        owner_ids: [organization.id],
        filter: {
          security_campaign_ids: [campaign.id],
        },
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

      # Notifications are sent by the GitHub org since there may be multiple campaign managers
      actor = GitHub.trusted_oauth_apps_owner
      repositories = Repository.where(id: repository_ids_with_open_alerts)

      # for each repo find the set of users that need to be notified
      all_user_ids_to_notify = repositories.flat_map do |repository|
        authzd_request = Authzd::Enumerator::ForSubjectRequest.new(
          subject_id: repository.id,
          subject_type: "Repository",
          actor_type: "User",
          options: Authzd::Enumerator::Options.new(relationship: "read"),
        )
        response = T.let(Authzd.enumerator_client.for_subject(authzd_request), Twirp::ClientResp[Authzd::Enumerator::ForSubjectResponse])
        if response.error.present?
          Failbot.report("Failed to load explicit recipients for security campaign creation notification")
          next []
        end

        authorized_user_ids = response.data.result_ids.to_a
        next [] if authorized_user_ids.empty?

        # Find all users that are subscribed to security alerts for the repository
        T.let(SecurityAlert.user_ids_subscribed_to_security_alerts(repository, authorized_user_ids), T::Array[Integer])
      end
      return if all_user_ids_to_notify.empty?

      # Check if these users are subscribed to email notifications
      users_to_notify = User.where(id: all_user_ids_to_notify).find_in_batches.to_a.flat_map(&:to_a)

      users_to_notify = users_to_notify.select do |user|
        settings = GitHub.newsies.settings(user)
        settings.success? && settings.subscribed_email?
      end
      return if users_to_notify.empty?

      # add new records if new users were found
      users_to_notify_ids = users_to_notify.map(&:id).uniq
      records_to_be_notified = users_to_notify_ids.map do |user_id|
        {
          security_campaign_id: campaign_id,
          user_id: user_id,
        }
      end

      with_write do
        records_to_be_notified.each_slice(1000) do |slice|
          SecurityCampaigns::SecurityCampaignUser.insert_all(slice)
        end

        repo_and_open_counts = {}
        data.repository_counts.each do |repo_counts|
          # Hashes can't have integer keys when used an an ActiveJob param
          repo_and_open_counts[repo_counts.repository_id.to_s] = repo_counts.open_count
        end

        # publish notify message
        SecurityCampaignUser.where(security_campaign: campaign, user_id: users_to_notify_ids).find_in_batches(batch_size: 1000) do |campaign_users|
          campaign_users.each do |subject|
            Notifyd::NotifyPublisher.new.async_publish(
              actor_id: actor.id,
              subject_id: subject.id,
              subject_klass: subject.class.name,
              context: {
                actor_id: actor.id,
                actor_login: actor.display_login,
                operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue.serialize,
                repo_counts_by_repo: repo_and_open_counts.to_json,
                alert_counts_by_repo: repo_and_open_counts,
              }
            )
          end
        end
      end
    end
  end
end
