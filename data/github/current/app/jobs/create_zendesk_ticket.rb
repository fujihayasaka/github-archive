# typed: true
# frozen_string_literal: true

# This job is enqueued from the contact form (https://support.github.com/contact),
# and creates a ticket in Zendesk so that GitHub support staff can respond.
class CreateZendeskTicket < ApplicationJob
  include GitHub::RateLimitable

  # Don't use the entire Zendesk API limit for creating tickets;
  # stop at MAX_CALLS_PER_MINUTE to give other apps some room.
  # See #with_rate_limit.
  RATE_LIMIT_KEY = "zendesk-api-calls"
  MAX_CALLS_PER_MINUTE = 200

  # Raised if the internal rate limit is reached.
  class RateLimitedError < RuntimeError
    attr_reader :retry_after

    def initialize(msg, retry_after)
      @retry_after = retry_after
      super(msg)
    end
  end

  # Tag the body of messages sent via the email fallback so they
  # can be identified on the Zendesk side. This is visible to users,
  # but Zendesk doesn't have a way to trigger actions based on email
  # headers.
  EMAIL_BODY_SUFFIX = "\n\n--\nThis ticket was created using the GitHub contact form."

  attr_reader :name, :email, :subject, :body, :opts
  queue_as :zendesk

  # Use a generous retry period, once every 2 minutes for 2 hours.
  # If ticket creation is still failing via the API after that time,
  # report an error and send the ticket via email.
  [Zendesk::ServerError, Zendesk::UnavailableError, Zendesk::TimeoutError].each do |error|
    retry_on(error, wait: 120, attempts: 120) do |job, error|
      job.report_error(error)
    end
  end

  # If Zendesk says the format is wrong, retrying is unlikely to help.
  # Send a fallback email so nothing is lost.
  discard_on(Zendesk::InvalidFormatError) do |job, error|
    job.report_error(error)
  end

  def report_error(error)
    if error.is_a?(Zendesk::ServerError)
      Failbot.push(status: error.status, retry_after: error.retry_after)
    end

    GitHub.dogstats.increment("create_ticket.zendesk_api.error",
      tags: [error.class.to_s.downcase])
    Failbot.report(error)
  end

  def perform(name, email, subject, body, opts = {})
    return if GitHub.enterprise?

    Failbot.push(app: "github-zendesk")
    @name = name
    @email = email
    @subject = subject
    @body = body
    @opts = opts

    with_rate_limit do
      GitHub.dogstats.time("create_ticket.zendesk_api.time") do
        response = zendesk.create_ticket(type: "incident",
          name: name,
          email: email,
          subject: subject,
          body: body,
          opts: opts)
      end
      GitHub.dogstats.increment("create_ticket.zendesk_api.created")
    end

  # Hitting either the internal rate limit (see with_rate_limit),
  # the Zendesk-imposed limit, or a 50x server error may return a
  # retry-after header. If that's present, reschedule the job after the
  # specified delay.
  #
  # Note that if the Zendesk API call fails but continues to return an
  # error with a retry-after header for every ticket creation attempt,
  # the job will be retried indefinitely (it'll never hit the retry_on
  # mechanism).
  rescue RateLimitedError, Zendesk::RateLimitedError, Zendesk::ServerError => error
    retry_or_raise(error)
  end

  def retry_or_raise(error)
    raise unless error.retry_after

    if error.is_a?(RateLimitedError)
      GitHub.dogstats.increment("create_ticket.internal.rate_limited")
    elsif error.is_a?(Zendesk::RateLimitedError)
      GitHub.dogstats.increment("create_ticket.zendesk_api.rate_limited")
    else
      GitHub.dogstats.increment("create_ticket.zendesk_api.server_retry")
    end

    CreateZendeskTicket.set(wait: error.retry_after)
      .perform_later(name, email, subject, body)
  end

  def with_rate_limit
    if rate_limit_increment(RATE_LIMIT_KEY, { max_tries: MAX_CALLS_PER_MINUTE, ttl: 60 }).at_limit?
      raise RateLimitedError.new("Reached internal rate limit", 60)
    else
      yield
    end
  end

  def zendesk
    @zendesk ||= Zendesk::Client.new
  end
end
