# typed: true
# frozen_string_literal: true

module Education
  module Twirp
    autoload :BaseClient, "education/twirp/base_client"
    autoload :NullClient, "education/twirp/null_client"
    autoload :HealthClient, "education/twirp/health_client"
    autoload :SchoolsClient, "education/twirp/schools_client"
    autoload :DiscountRequestsClient, "education/twirp/discount_requests_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class NotFoundError < BaseError; end
    class TimeoutError < BaseError; end

    def self.schools_client(user:)
      @schools_client ||= SchoolsClient.new(user:)
    end

    def self.discount_requests_client(user:)
      @discount_requests_client ||= DiscountRequestsClient.new(user:)
    end

    def self.health_client(user:)
      @health_client ||= HealthClient.new(user:)
    end
  end
end
