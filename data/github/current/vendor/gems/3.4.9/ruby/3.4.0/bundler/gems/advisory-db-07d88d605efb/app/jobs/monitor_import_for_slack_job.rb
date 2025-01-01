# frozen_string_literal: true

class MonitorImportForSlackJob < ApplicationJob
  LOADING = ":pb--clock:"
  DONE = ":pb--check:"
  ERROR = ":pb--x:"

  queue_as :high

  attr_reader :import, :progress, :slack_message_ts

  def perform(import)
    return unless AdvisoryDB.slack_enabled? && AdvisoryDB.slack_channel.present?

    @import = import
    @progress = import.progress

    create_slack_message
    listen_for_progress unless progress.finished?
  end

  private

  def listen_for_progress
    progress.subscribe do |event|
      case event
      when :increment
        update_slack_message unless too_soon?
      when :finish
        progress.unsubscribe
        update_slack_message
      when :timeout
        interrupted!
        reload
        update_slack_message
      end
    end
  end

  def interrupted!
    @interrupted = true
  end

  def interrupted?
    @interrupted && !progress.finished?
  end

  def too_soon?
    @soon&.future?
  end

  def reload
    @import = import.class.find(import.id) # Hard reload
    @progress = @import.progress
  end

  def create_slack_message
    response = AdvisoryDB.slack.chat_postMessage(slack_message_attributes)
    @slack_message_ts = response.fetch("ts")
  end

  def update_slack_message
    AdvisoryDB.slack.chat_update(slack_message_attributes)
    @soon = 2.seconds.from_now
  end

  def slack_message_attributes
    {
      channel: AdvisoryDB.slack_channel,
      attachments: [
        {
          title: slack_message_title,
          text: slack_message_text,
          fallback: slack_message_fallback,
          color: slack_message_color,
          fields: slack_message_fields,
        },
      ],
      as_user: true,
    }.tap do |attributes|
      attributes[:ts] = slack_message_ts if slack_message_ts
    end
  end

  def slack_message_title
    "#{import.source.titleize} Import"
  end

  def slack_message_text
    status =
      if interrupted?
        ERROR
      elsif progress.finished?
        DONE
      else
        LOADING
      end

    bar = SlackProgressBar.new(
      counts: {
        created: progress.count(:created),
        updated: progress.count(:updated),
        errored: progress.count(:errored),
        skipped: progress.count(:skipped),
      },
      total: progress.total,
    )

    percentage = "#{progress.percentage.to_i}%"

    text = "#{status}#{bar}#{percentage}"
    text = "Progress was interrupted!\n#{text}" if interrupted?
    text
  end

  def slack_message_fallback
    if interrupted?
      "#{import.source.humanize} import was interrupted after #{progress.percentage.to_i}% completion."
    else
      "#{import.source.humanize} import is #{progress.percentage.to_i}% complete."
    end
  end

  def slack_message_color
    if interrupted?
      "#d02000"
    elsif progress.finished?
      "#00b050"
    else
      "#dddddd"
    end
  end

  def slack_message_fields
    return [] unless progress.finished?

    [
      {
        title: "Created",
        value: ":pb-g-o: #{ActiveSupport::NumberHelper.number_to_delimited(progress.count(:created))}",
        short: true,
      },
      {
        title: "Updated",
        value: ":pb-b-o: #{ActiveSupport::NumberHelper.number_to_delimited(progress.count(:updated))}",
        short: true,
      },
      {
        title: "Errored",
        value: ":pb-r-o: #{ActiveSupport::NumberHelper.number_to_delimited(progress.count(:errored))}",
        short: true,
      },
      {
        title: "Skipped",
        value: ":pb-y-o: #{ActiveSupport::NumberHelper.number_to_delimited(progress.count(:skipped))}",
        short: true,
      },
    ]
  end
end
