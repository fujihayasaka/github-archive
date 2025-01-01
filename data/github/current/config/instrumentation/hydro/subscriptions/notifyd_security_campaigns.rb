# typed: true
# frozen_string_literal: true

require "notifyd-client"

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("security_campaigns.security_campaign_repository_notification") do |payload|
    next unless payload[:security_campaign] && payload[:actor] && payload[:repository_ids]

    subjects = SecurityCampaigns::SecurityCampaignRepository.includes(:repository).where(security_campaign: payload[:security_campaign], repository_id: payload[:repository_ids])

    subjects.each do |subject|
      Notifyd::NotifyPublisher.new.async_publish(
        actor_id: payload[:actor].id,
        subject_id: subject.id,
        subject_klass: subject.class.name,
        context: {
          actor_id: payload[:actor].id,
          actor_login: payload[:actor].display_login,
          operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Create.serialize,
        }
      )
    end
  end

  subscribe("security_campaigns.security_campaign_user_notification") do |payload|
    next unless payload[:security_campaign_id] && payload[:actor] && payload[:user_ids]

    subjects = SecurityCampaigns::SecurityCampaignUser.where(
      security_campaign_id: payload[:security_campaign_id],
      user_id: payload[:user_ids]
    )

    subjects.each do |subject|
      Notifyd::NotifyPublisher.new.async_publish(
        actor_id: payload[:actor].id,
        subject_id: subject.id,
        subject_klass: subject.class.name,
        context: {
          actor_id: payload[:actor].id,
          actor_login: payload[:actor].display_login,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create.serialize,
        }
      )
    end
  end
end
