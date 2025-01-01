# typed: true
# frozen_string_literal: true

require "github/config/sendgrid"
require "faraday"

module GitHub
  class Sendgrid
    autoload :Error, "github/sendgrid/error"

    include Instrumentation::Model

    attr_reader :email

    def initialize(email)
      unless email.is_a?(UserEmail)
        raise ArgumentError, "email must be a UserEmail"
      end
      @email = email
    end

    # Remove a bounce suppression
    #
    # Sendgrid will return a 204 if the mail address has been removed, or simply was not on that list.
    # Any other response code is considered an error and treated as such.
    def remove_bounce_suppression
      GitHub.dogstats.time("sendgrid.remove_bounce_suppression") do
        GitHub::Logger::log({ "app" => "sendgrid-suppression", "action" => "remove", "email" => @email.email })
        sg = Faraday.new "https://api.sendgrid.com"
        begin
          resp = sg.delete do |req|
            req.url "/v3/suppression/bounces"
            req.headers["Authorization"] = "Bearer #{GitHub::Config::Sendgrid.api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.encode({ "emails": [@email.email] })
          end
          if resp.status != 204
            raise Error.new(resp, :remove_bounce_suppression)
          end
          GitHub.dogstats.increment "sendgrid.bounce_suppressions_removed"
        rescue Faraday::Error => boom
          raise Error.new(boom, :remove_bounce_suppression)
        end
      end
      instrument :remove_bounce_suppression
    end

    def event_payload
      if @email
        {
          email:    @email.email,
          email_id: @email.id,
          user:     @email.user,
          user_id:  @email.user_id,
        }
      else
        {}
      end
    end

    def event_prefix
      :sendgrid
    end
  end
end
