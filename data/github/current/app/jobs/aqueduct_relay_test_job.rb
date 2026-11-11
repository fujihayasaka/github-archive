# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class AqueductRelayTestJob < ApplicationJob
  self.queue_adapter = :aqueduct

  schedule interval: 30.seconds, condition: -> { !GitHub.enterprise? }

  queue_as :aqueduct_test

  def self.perform_later(_ = nil)
    T.bind(self, T.untyped)
    super(Time.now.to_f)
  end

  def perform(timestamp)
    lag_ms = (Time.now.to_f - timestamp.to_f * 1_000)
    GitHub.dogstats.distribution("aqueduct_job_relay.rtt", lag_ms)
  end
end
