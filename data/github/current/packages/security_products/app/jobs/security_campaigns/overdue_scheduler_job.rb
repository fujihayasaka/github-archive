# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job will schedule a job to send a notification for every security campaign that will be overdue in the
  # next two hours and hasn't already been scheduled.
  class OverdueSchedulerJob < ApplicationJob
    queue_as :security_campaigns

    # This is a cross tenant scheduling job
    exempt_from_tenant_context_requirement

    retry_on_dirty_exit

    schedule interval: 1.hour.freeze, condition: -> { !GitHub.enterprise? }
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    # The "event horizon" for which we'll schedule overdue notifications. This is double the schedule interval to
    # ensure we don't miss any campaigns when the job doesn't run exactly every hour.
    EVENT_HORIZON = T.let(2.hours.freeze, ActiveSupport::Duration)

    LAST_EVENT_HORIZON_KEY = "security-campaigns-overdue-scheduler-job-last-event-horizon"

    sig { void }
    def perform
      return if GitHub.enterprise?
      return if GitHub.flipper[:security_campaigns_disable_overdue_scheduler_job].enabled?

      # Get the last event horizon. If we don't have one, default to the current time so we don't schedule notifications
      # for campaigns that were overdue before the job started running.
      last_event_horizon = Time.at(CodeScanning::KV.store.get(LAST_EVENT_HORIZON_KEY).value!&.to_i || Time.now.utc.to_i).to_datetime

      # Look ahead to the next event horizon
      event_horizon = Time.now.utc.to_datetime + EVENT_HORIZON

      # Find all security campaigns that end between the last event horizon and the new event horizon and schedule a job
      # to send overdue notifications for each of them
      SecurityCampaigns::SecurityCampaign.open.where("ends_at > ? AND ends_at <= ?", last_event_horizon, event_horizon).find_in_batches(batch_size: 10) do |campaigns|
        campaigns.each do |campaign|
          GitHub::CurrentTenant.set(campaign.organization&.business) do
            # Schedule the job at its end date, unless the end date is in the past in which case we'll run it immediately
            wait_until = campaign.ends_at.to_i > Time.now.utc.to_i ? campaign.ends_at : nil

            SecurityCampaigns::SendOverdueNotificationJob.set(wait_until:).perform_later(campaign_id: campaign.id)
            SecurityCampaigns::PostCampaignOverdueCommentsJob.set(wait_until:).perform_later(campaign_id: campaign.id)
          end
        end
      end

      with_write do
        CodeScanning::KV.store.set(LAST_EVENT_HORIZON_KEY, event_horizon.to_time.to_i.to_s, expires: 1.year.from_now)
      end
    end
  end
end
