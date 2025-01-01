# typed: true
# frozen_string_literal: true

module Newsies
  class EmailHandler
    # @see Newsies::DeliverNotificationsJob::Inspector
    class NullInspector
      def enabled?
        false
      end

      def log(msg = nil)
      end
    end

    # Public: Handles the delivery of an email for the User.
    #
    # delivery - A Newsies::Delivery object.
    # user     - The delivery recipient User.
    # settings - A Newsies::Settings object of the user receiving this
    #            notification.
    # options  - A Hash with message-specific options
    #            :reason   - Symbol reason for sending the email:
    #                        :mention, :team_mention, :assign, :author, nil
    #            :priority - Priority of this notification (:low or :high)
    #
    # Returns true if delivered, or false.
    def deliver(delivery, user, settings, options = nil)
      # This inspector is used to debug mail delivery at runtime.
      # It is related to the feature flag :notifications_extra_logging_for_newsies_deliver_notifications_job
      # Once this feature flag is removed this can be removed as well
      inspector = options[:inspector] || NullInspector.new

      message = Newsies::Emails::MessageResolver.message_for(delivery, user, settings, options)
      unless message.deliverable?
        reason = message.undeliverable_reason || "deliverable_check"
        inspector.log do
          {
            message: "the message is not deliverable, reason: #{reason}",
            message_type: message.class.name,
            handler: :email,
          }
        end
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["filter:#{reason}", "type:filter", "handler:#{handler_key}"])
        return false
      end

      if message.blocked_by_organization_restriction?
        inspector.log do
          {
            message: "the message is blocked by organization restriction",
            message_type: message.class.name,
            handler: :email,
          }
        end
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["filter:organization_restriction", "type:filter", "handler:#{handler_key}"])
        return false
      end

      delivered = false
      mail = nil

      GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:potential_after_filters", "handler:#{handler_key}"])

      # Returns a Mail::Message to be delivered.
      #
      # If the mailer method called prevents delivery for any reason, an
      # instance of ActionMailer::Base::NullMail is returned instead. Calling
      # deliver_now on this object returns nil and does nothing.
      mail = ::NewsiesMailer.notification(message)

      inspector.log do
        {
          message: "mail generated",
          mail_instance: mail.class.name,
        }
      end

      # Returns the mail if delivered or nil otherwise.
      delivered = send_mail(mail: mail, user: user, inspector: inspector)

      DeliveryLogger.log_to_datadog(
        handler_key: handler_key,
        event_time: options[:event_time],
        extra_tags: options[:extra_tags],
      )

      # If `deliver_later` is used, this logging will actually be being sent prematurely
      # this is non-ideal but known. Ultimately we should move this to happen after the
      # email is _actually_ delivered. See https://github.com/github/notifications/issues/858 for more.
      if delivered
        DeliveryLogger.log_to_splunk_and_hydro(
          delivery,
          user: user,
          reason: options[:reason],
          handler_key: handler_key,
          event_time: options[:event_time],
          root_job_enqueued_at: options[:root_job_enqueued_at],
          email: message.recipient_email,
          delivered: delivered,
        )
      else
        # In this case we don't want to log to hydro
        DeliveryLogger.log_to_splunk(
          delivery,
          user: user,
          reason: options[:reason],
          handler_key: handler_key,
          event_time: options[:event_time],
          root_job_enqueued_at: options[:root_job_enqueued_at],
          email: message.recipient_email,
          delivered: delivered,
        )
      end

      delivered
    rescue => e # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:error", "handler:#{handler_key}"])
      inspector&.log do
        {
          message: "email delivery failed with error: #{e.message}",
          handler: :email,
          error: e.class.name,
        }
      end

      raise e
    end

    # Public: Gets the key that identifies this Handler.
    #
    # Returns a Symbol.
    def handler_key
      :email
    end

    private

    def send_mail(mail:, user:, inspector:)
      result = mail.deliver_now
      inspector.log do
        {
          message: "mail#delivery_now called",
        }
      end
      delivered = !!result

      if delivered
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:success", "handler:#{handler_key}"])
      else
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:error", "handler:#{handler_key}"])
      end

      delivered
    end
  end
end
