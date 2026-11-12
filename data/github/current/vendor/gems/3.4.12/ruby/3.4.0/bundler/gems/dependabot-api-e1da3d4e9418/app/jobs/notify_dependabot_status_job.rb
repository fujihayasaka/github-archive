# frozen_string_literal: true

class NotifyDependabotStatusJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  VALIDITY_PERIOD = 2.days
  NOTIFY_DEPENDABOT_RETRY_INTERVAL = 3.hours

  def perform
    channel = "#dependabot-ops"
    paused_status, pause_timestamp = fetch_paused_status

    if paused_status
      handle_paused_status(channel, pause_timestamp)
    else
      notify_resumed_status(channel)
    end
  end

  private

  def fetch_paused_status
    paused_status = Dependabot.redis.get("dependabot_paused_status") == "true"
    pause_timestamp = Dependabot.redis.get("dependabot_pause_timestamp")
    pause_timestamp = Time.zone.at(pause_timestamp.to_i) if pause_timestamp
    [paused_status, pause_timestamp]
  end

  def handle_paused_status(channel, pause_timestamp)
    if within_validity_period?(pause_timestamp)
      notify_paused_status(channel)
      reenqueue_job
    else
      notify_validity_expired(channel)
    end
  end

  def notify_paused_status(channel)
    send_chatops_message(
      channel: channel,
      message: ":information_source: Dependabot is currently paused. " \
               "Status updates will continue every #{NOTIFY_DEPENDABOT_RETRY_INTERVAL.inspect} until resumed."
    )
  end

  def notify_validity_expired(channel)
    send_chatops_message(
      channel: channel,
      message: ":warning: Dependabot pause validity period has expired. " \
               "Notifications will stop until further action is taken."
    )
  end

  def notify_resumed_status(channel)
    send_chatops_message(
      channel: channel,
      message: ":white_check_mark: Dependabot has been resumed. Regular status notifications have stopped."
    )
  end

  def reenqueue_job
    NotifyDependabotStatusJob.set(wait: NOTIFY_DEPENDABOT_RETRY_INTERVAL).perform_later
  end

  def within_validity_period?(pause_timestamp)
    return false unless pause_timestamp

    Time.current <= pause_timestamp + VALIDITY_PERIOD
  end

  def send_chatops_message(channel:, message:)
    ChatopsController.new.jsonrpc_success(message, options: { channel: channel })
  rescue StandardError => e
    Dependabot::Logger.info(
      msg: "Failed to send Chatops message: #{e.message}",
      "code.namespace": "NotifyDependabotStatusJob"
    )
  end
end
