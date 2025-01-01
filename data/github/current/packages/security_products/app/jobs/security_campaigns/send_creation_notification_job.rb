# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job will schedule a job to send a notification for every security campaign that will be overdue in the
  # next two hours and hasn't already been scheduled.
  class SendCreationNotificationJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(actor_id: Integer, campaign_id: Integer, repo_ids: T::Array[Integer]).void }
    def perform(actor_id:, campaign_id:, repo_ids:)
      return if GitHub.enterprise?

      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: campaign_id)
      return if campaign.nil?
      return unless T.must(campaign.organization).feature_enabled?(:security_campaigns_one_email_per_campaign)

      actor = User.find_by(id: actor_id)
      return if actor.nil?

      repositories = Repository.where(id: repo_ids)

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
      users_to_notify = T.must(User.where(id: all_user_ids_to_notify.to_set).find_each).select do |user|
        settings = GitHub.newsies.settings(user)
        settings.success? && settings.subscribed_email?
      end

      return if users_to_notify.empty?

      with_write do
        SecurityCampaigns::SecurityCampaignUser.insert_all(
          users_to_notify.map do |user|
            {
              security_campaign_id: campaign_id,
              user_id: user.id,
            }
          end
        )
      end

      GlobalInstrumenter.instrument("security_campaigns.security_campaign_user_notification", {
        actor:,
        security_campaign_id: campaign.id,
        user_ids: users_to_notify.map(&:id).to_set,
      })
    end
  end
end
