# typed: true
# frozen_string_literal: true

module GitHub
  class AuthzdInstrumenter
    class << self
      delegate :authorize_requests, :batch_authorize_requests, :enabled?, :enable, :reset, to: :collector
    end

    def self.collector
      GitHub::DataCollector::AuthzdCollector.get_instance
    end

    def self.total_request_time
      authorize_requests.sum { |r| r[:duration_ms] } +
        batch_authorize_requests.sum { |r| r[:duration_ms] }
    end

    def self.total_request_count
      authorize_request_count + batch_authorize_request_count
    end

    def self.authorize_request_count
      authorize_requests.size
    end

    def self.batch_authorize_request_count
      batch_authorize_requests.size
    end

    def self.any?
      authorize_requests.any? || batch_authorize_requests.any?
    end

    def self.track_authorize(request)
      authorize_requests << request
    end

    def self.track_batch_authorize(request)
      batch_authorize_requests << request
    end
  end
end
