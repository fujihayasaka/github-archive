# typed: true
# frozen_string_literal: true

module Zendesk
  # A generic error; superclass of all the following errors.
  class Error < RuntimeError; end

  # Raised if the Zendesk API cannot be contacted.
  class UnavailableError < Error; end

  # A timeout has occurred somewhere in the request path.
  class TimeoutError < Error; end

  # Zendesk has refused the API request because it doesn't meet
  # a requirement; a field's value may be invalid, or a required
  # field is missing.
  class InvalidFormatError < Error; end

  # A failure has occured on the Zendesk side. If `retry_after` is
  # set, wait at least that many seconds before trying again.
  class ServerError < Error
    attr_reader :status, :retry_after

    def initialize(msg: nil, status: nil, retry_after: nil)
      @status = status
      @retry_after = retry_after.to_i if retry_after
      super(msg)
    end
  end

  # A rate limit has been hit. Wait at least `retry_after` seconds before
  # trying again. See also
  # https://developer.zendesk.com/rest_api/docs/support/introduction#rate-limits
  class RateLimitedError < ServerError; end

  # This class implements a tiny API client for Zendesk. It provides just
  # a single method to create a ticket; that's all the functionality
  # github/github currently needs.
  class Client

    # Public: Create a ticket in Zendesk.
    #
    # type    - Either "question", "incident", "problem", or "task".
    # name    - Name of the person opening the ticket.
    # email   - Email address where they can be contacted.
    # subject - Ticket subject.
    # body    - Ticket body.
    # opts    - A hash of additional fields to set on the ticket.
    #
    # See https://support.zendesk.com/hc/en-us/articles/203661506-About-ticket-fields
    # for details on the available ticket types, and
    # https://developer.zendesk.com/rest_api/docs/support/tickets#json-format for
    # the available fields.
    #
    # Examples
    #
    #   Zendesk::Client.new.create_ticket(type: "Incident",
    #     name: "Monalisa Octocat",
    #     email: "mona@github.com",
    #     subject: "Just testing",
    #     body: "It's only a model.",
    #     opts: {
    #       brand_id: 12345,
    #       tags: %w( example test )
    #     }
    #   )
    #
    # Returns a Faraday::Response from the Zendesk API.
    # Raises a Zendesk::Error if a failure occurs.
    def create_ticket(type:, name:, email:, subject:, body:, opts: {})
      GitHub.logger.tagged("code.namespace": self.class.name, "code.function": __method__) do
        ticket = {
          ticket: {
            type: type,
            subject: subject,
            comment: { body: body },
            requester: { name: name, email: email },
          },
        }.tap do |ticket|
          if fields = opts.delete(:custom_fields)
            # Ensure that custom fields are keyed by their integer ID, not string.
            # ActiveJob can only serialize hashes with string or symbol keys, so
            # we'll get strings from the CreateZendeskTicket job.
            ticket[:ticket][:custom_fields] = fields.map { |id, val| { id.to_i => val } }
          end

          ticket[:ticket].merge!(opts)
        end

        begin
          response = conn.post("/api/v2/tickets.json", ticket.to_json)
          return response if response.success?

          case response.status
          when 422
            GitHub.logger.error(
              InvalidFormatError.new(msg: response.body),
              "http.status": response.status,
            )
            raise InvalidFormatError.new(status: response.status)
          when 429
            GitHub.logger.error(
              RateLimitedError.new(msg: response.body, status: response.status, retry_after: response.headers["Retry-After"]),
              "http.status": response.status,
            )
            raise RateLimitedError.new(status: response.status, retry_after: response.headers["Retry-After"])
          else
            GitHub.logger.error(
              ServerError.new(msg: response.body, status: response.status, retry_after: response.headers["Retry-After"])
            )
            raise ServerError.new(status: response.status, retry_after: response.headers["Retry-After"])
          end
        rescue Faraday::ConnectionFailed
          raise UnavailableError
        rescue Faraday::TimeoutError, Timeout::Error
          raise TimeoutError
        end
      end
    end

    # Internal: Faraday connection used to contact the Zendesk API.
    def conn
      @conn ||= begin
        Faraday.new(url: GitHub.zendesk_api_url) do |f|
          f.adapter Faraday.default_adapter
          f.headers = {
            "Authorization" => "Basic #{GitHub.zendesk_api_token}",
            "Content-Type" => "application/json",
            "Accept" => "application/json",
            "User-Agent" => "github-monolith/#{GitHub.current_head}",
          }
        end
      end
    end
  end
end
