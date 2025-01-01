# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class AuthzdCollector < Collector
      set_callback :reset, :after do |collector|
        collector.authorize_requests = []
        collector.batch_authorize_requests = []
      end

      attributes :authorize_requests, :batch_authorize_requests

      def self.collector_name
        :authzd_collector
      end
    end
  end
end
