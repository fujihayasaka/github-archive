# typed: false
# frozen_string_literal: true

module Resqued
  class MetricsServer
    def self.start(address: ENV["RESQUED_METRICS_SERVER_ADDRESS"])
      return if address.blank?
      Thread.new do # rubocop:disable GitHub/ThreadUse
        pid = spawn("bin/safe-ruby", "script/resqued-metrics-server", "-D", "--http", address)
        Process.waitpid(pid)
      end
    end
  end
end
