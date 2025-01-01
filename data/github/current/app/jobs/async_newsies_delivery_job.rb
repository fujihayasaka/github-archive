# typed: false
# frozen_string_literal: true

class AsyncNewsiesDeliveryJob < ApplicationDeliveryJob
  include Newsies::SloHelper
  QUEUE_NAME = "newsies_mailer"

  # if the last argument to the mailer is an options hash with a priority: :low
  # the job will be queued onto the low priority mailer queue
  queue_as do
    args = self.arguments.last

    if self.arguments.any?
      args = args[:args]&.last
    end

    next "#{self.class::QUEUE_NAME}_low" if args.try(:fetch, :priority, nil) == :low
    self.class::QUEUE_NAME
  end

  def perform(mailer, mail_method, delivery_method, *args, **kwargs)
    super
    # extract the options hash passed to AsyncNewsiesMailer.notification_from_ids.
    options = kwargs.dig(:args, 4) || {}

    extra_tags = options[:extra_tags] || []
    extra_tags << "async:true"

    Newsies::DeliveryLogger.log_to_datadog(
      handler_key: :email,
      event_time: options[:event_time],
      extra_tags: extra_tags
    )
  end

  retry_on AsyncNewsiesMailer::MissingArgumentsError, attempts: 6, wait: :polynomially_longer do
    # If after 6 retries (around 20 minutes) we still cannot find the record on
    # we replica we assume it has been deleted. At this point we discard the error and stop retrying.
  end
end
