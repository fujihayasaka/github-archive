# frozen_string_literal: true

require "rails_helper"
require "freno/throttler_instrumenter"

RSpec.describe Freno::ThrottlerInstrumenter do
  subject(:instrumenter) { described_class.new }

  describe "#called" do
    it "increments the counter" do
      expect(MetricsClient).to receive(:increment).
        with("freno.throttler.called", tags: { cluster: "mysqla,mysqlb" })
      instrumenter.instrument("throttler.called", { store_names: %w(mysqla mysqlb), waited: 0 })
    end
  end

  describe "#waited" do
    it "increments the counter" do
      expect(MetricsClient).to receive(:histogram).
        with("freno.throttler.waited", 1.5, tags: { cluster: "mysqla,mysqlb" })
      instrumenter.instrument("throttler.waited", { store_names: %w(mysqla mysqlb), waited: 1.5 })
    end
  end

  describe "#waited_too_long" do
    it "increments the counter" do
      expect(MetricsClient).to receive(:increment).
        with("freno.throttler.timed_out", tags: { cluster: "mysqla,mysqlb" })
      instrumenter.instrument("throttler.waited_too_long", { store_names: %w(mysqla mysqlb) })
    end
  end

  describe "#freno_errored" do
    it "increments the counter" do
      expect(MetricsClient).to receive(:increment).
        with("freno.throttler.freno_error", tags: { cluster: "mysqla,mysqlb" })
      instrumenter.instrument("throttler.freno_errored", { store_names: %w(mysqla mysqlb) })
    end
  end

  describe "#circuit_open" do
    it "increments the counter" do
      expect(MetricsClient).to receive(:increment).
        with("freno.throttler.circuit_open", tags: { cluster: "mysqla,mysqlb" })
      instrumenter.instrument("throttler.circuit_open", { store_names: %w(mysqla mysqlb) })
    end
  end
end
