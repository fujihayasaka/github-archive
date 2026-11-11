# frozen_string_literal: true

module GitHubThrottle
  class Middleware < Faraday::Middleware
    def call(request_env)
      GitHubThrottle.take_ticket
      @app.call(request_env)
    end
  end

  class RateLimit
    WINDOW = 3600.0 # GitHub rate limits its API in one hour windows.

    attr_accessor :github_rate_limit

    delegate :limit, :remaining, :resets_at, :resets_in, to: :github_rate_limit

    def initialize
      refresh
    end

    def current?
      resets_at.future?
    end

    def active?
      limit > remaining
    end

    def interval
      WINDOW / limit
    end

    def refresh
      fetch

      unless active?
        activate
        fetch
      end

      self
    end

    private

    def fetch
      self.github_rate_limit = AdvisoryDB.github.rate_limit!

      ActiveSupport::Notifications.instrument("fetch_rate_limit.github_throttle", rate_limit: self)
    end

    # Make a request that counts against the rate limit.
    def activate
      AdvisoryDB.github.root
    end
  end

  TICKET_KEY = "github-throttle:ticket"
  TIMEOUT = 60 # seconds

  Error = Class.new(::StandardError)
  ClosedError = Class.new(Error)
  TimeoutError = Class.new(Error)

  extend self

  def open?
    AdvisoryDB.github_throttle_open?
  end

  def take_ticket
    return if open?

    ActiveSupport::Notifications.instrument("take_ticket.github_throttle") do |payload|
      _key, ticket = redis.brpop(TICKET_KEY, timeout: TIMEOUT)

      if ticket
        payload[:timeout] = false
        payload[:ticket] = ticket
      else
        payload[:timeout] = true
        raise TimeoutError, "GitHub client timed out while waiting for a ticket."
      end

      ticket
    end
  end

  def print_tickets
    unless open?
      raise ClosedError, "GitHub throttle must be open to print tickets."
    end

    rate_limit = RateLimit.new

    loop do
      rate_limit.refresh

      while rate_limit.current?
        sleep(rate_limit.interval)
        print_ticket
      end
    end
  end

  def print_ticket
    ticket = format("%0.6f", Time.now.to_f)

    redis.multi do |multi|
      multi.del(TICKET_KEY)
      multi.lpush(TICKET_KEY, ticket)
    end

    ActiveSupport::Notifications.instrument("print_ticket.github_throttle", ticket: ticket)

    ticket
  end

  private

  def redis
    AdvisoryDB.redis
  end
end
