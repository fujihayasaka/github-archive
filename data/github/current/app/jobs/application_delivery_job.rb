# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class ApplicationDeliveryJob < ApplicationJob
  queue_as :mailers

  # We don't/can't fix _every_ exception, we are happy for some to continue
  # to fail silently as if raise_delivery_errors was set to false.
  #
  # DISCARD_EXCEPTIONS acts as an allow list of exceptions that we are happy to
  # fail silently.
  DISCARD_EXCEPTIONS = [
    { class: Net::SMTPFatalError, message: "Recipient address rejected: User unknown in local recipient table" },
    { class: Net::SMTPFatalError, message: "message file too big" },
    { class: Net::SMTPSyntaxError, message: "Bad recipient address syntax" },
  ]

  RETRY_ON_ERRORS = [
    Net::SMTPError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    IOError,
    SocketError,
    Errno::ECONNRESET
  ]

  LOG_TO_FAILBOT_ERRORS = [
    Net::SMTPAuthenticationError,
    Net::SMTPFatalError,
    Net::SMTPSyntaxError,
    Net::SMTPUnknownError,
    Net::SMTPUnsupportedCommand
  ]

  HANDLED_ERRORS = Set[*RETRY_ON_ERRORS, *LOG_TO_FAILBOT_ERRORS].to_a

  retry_on *RETRY_ON_ERRORS, wait: :polynomially_longer

  rescue_from ActiveJob::DeserializationError do |error|
    record_error(error)

    mailer, mail_method, delivery_method = @serialized_arguments
    GitHub.dogstats.increment("active_job.application_delivery_job.error", tags: [
      "mailer:#{mailer}",
      "mailer_method:#{mail_method}",
      "delivery_method:#{delivery_method}",
      "error:#{error.class.name.underscore}",
    ])

    context = {
      mailer: mailer,
      mailer_method: mail_method,
      deliver_method: delivery_method,
    }
    Failbot.report(error, context)
  end

  resolve_tenant_context do |mailer, mail_method, _delivery_method, options = {}|
    args = Array(options[:args])
    mailer.constantize.resolve_tenant(mail_method, args) if mailer.constantize.respond_to?(:resolve_tenant)
  end

  before_enqueue do
    throw :abort if ActionMailer::Base.delivery_method == :smtp && !GitHub.smtp_enabled?
  end

  def perform(mailer, mail_method, delivery_method, args:)
    GitHub.dogstats.increment("active_job.application_delivery_job", tags: [
                                "mailer:#{mailer}",
                                "mailer_method:#{mail_method}",
                                "delivery_method:#{delivery_method}",
                              ])

    mail = mailer.constantize.public_send(mail_method, *args)
    mail.raise_delivery_errors = true
    mail.send(delivery_method)
  rescue *HANDLED_ERRORS => e
    return if discard_exception?(e)
    # We  want to know about the errors in LOG_TO_FAILBOT_ERRORS quickly so we are able to resolve.
    # However, we don't want to drop the mail on the floor, so here we report the error via failbot
    # and then re-raise the error which will be caught by the retry_on hook.
    Failbot.report(e) if LOG_TO_FAILBOT_ERRORS.include?(e.class)
    raise
  end

  private

  # Private: decides whether the exception should discarded or logged and retried.
  #
  # Some exceptions with certain messages are excluded from logging as a wontfix
  # exception. These are generally exceptions which are not transient.
  # By doing this we are exhibitting behavior as if raise_delivery_errors was false
  # for specific exceptions and messages rather than a blanket rule for all exceptions.
  #
  # returns Boolean
  def discard_exception?(e)
    DISCARD_EXCEPTIONS.find { |log_exclusion| log_exclusion[:class] == e.class && e.message.include?(log_exclusion[:message]) }
  end
end
