# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job will schedule a job to send a notification for every security campaign that will be overdue in the
  # next two hours and hasn't already been scheduled.
  class SendCreationNotificationJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(campaign_id: Integer, repo_ids: T::Array[Integer]).void }
    def perform(campaign_id:, repo_ids:)
      return if GitHub.enterprise?

      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      return if campaign.nil? || campaign.spammy?

      actor = GitHub.trusted_oauth_apps_owner

      repositories = Repository.where(id: repo_ids)

      # for each repo find the set of users that need to be notified
      all_user_ids_to_notify = repositories.flat_map do |repository|
        if SecurityCampaigns.notifications_for_code_scanning_read?(T.must(campaign.organization))
          authorized_repo_write_user_ids = repository.user_ids_with_privileged_access(min_action: :write)

          authorized_read_repo_user_ids = get_authorized_user_ids_for_repository(repository)
          next [] if authorized_read_repo_user_ids.empty? # We assume that all write access users have also read access

          read_only_repo_user_ids = authorized_read_repo_user_ids - authorized_repo_write_user_ids
          read_only_repo_users = User.where(id: read_only_repo_user_ids)

          filtered_read_repo_user_ids = []
          if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, campaign.organization, campaign.organization&.business, default: false) && campaign.alert_type? == "secret_scanning"
            read_only_repo_users.each_slice(100) do |user_batch|
              batch_results = Promise.all(user_batch.map do |user|
                repository.can_view_secret_scanning_alerts?(user).then do |allowed|
                  if allowed
                    user.id
                  else
                    nil
                  end
                end
              end).sync.compact

              filtered_read_repo_user_ids.concat(batch_results)
            end
          else
            read_only_repo_users.each_slice(100) do |user_batch|
              batch_results = Promise.all(user_batch.map do |user|
                repository.async_code_scanning_allowed?(:read_code_scanning, user).then do |allowed|
                  if allowed
                    user.id
                  else
                    nil
                  end
                end
              end).sync.compact

              filtered_read_repo_user_ids.concat(batch_results)
            end
          end
          authorized_repo_write_user_ids + filtered_read_repo_user_ids
        else
          authorized_user_ids = get_authorized_user_ids_for_repository(repository)
          next [] if authorized_user_ids.empty?

          # Find all users that are subscribed to security alerts for the repository
          T.let(SecurityAlert.user_ids_subscribed_to_security_alerts(repository, authorized_user_ids), T::Array[Integer])
        end
      end

      return if all_user_ids_to_notify.empty?

      # Check if these users are subscribed to email notifications
      if !SecurityCampaigns.notifications_for_code_scanning_read?(T.must(campaign.organization))
        all_user_ids_to_notify = User.where(id: all_user_ids_to_notify.to_set).find_each.select do |user|
          Notifications::Settings.watcher_email?(user)
        end.pluck(:id)
      end

      with_write do
        SecurityCampaigns::SecurityCampaignUser.insert_all(
          all_user_ids_to_notify.map do |user_id|
            {
              security_campaign_id: campaign_id,
              user_id: user_id,
            }
          end
        )
      end

      subjects = SecurityCampaigns::SecurityCampaignUser.where(
        security_campaign: campaign,
        user_id: all_user_ids_to_notify.to_set,
      )

      subjects.each do |subject|
        Notifyd::NotifyPublisher.new.async_publish(
          actor_id: actor.id,
          subject_id: subject.id,
          subject_klass: subject.class.name,
          context: {
            actor_id: actor.id,
            actor_login: actor.display_login,
            operation: Notifyd::Operations::SecurityCampaignUserOperation::Create.serialize,
          }
        )
      end
    end

    private

    sig { params(repository: Repository).returns(T::Array[Integer]) }
    def get_authorized_user_ids_for_repository(repository)
      authzd_request = Authzd::Enumerator::ForSubjectRequest.new(
        subject_id: repository.id,
        subject_type: "Repository",
        actor_type: "User",
        options: Authzd::Enumerator::Options.new(relationship: "read"),
      )
      response = T.let(Authzd.enumerator_client.for_subject(authzd_request), Twirp::ClientResp[Authzd::Enumerator::ForSubjectResponse])
      if response.error.present?
        Failbot.report("Failed to load explicit recipients for security campaign creation notification")
        return []
      end

      response.data.result_ids.to_a
    end
  end
end
