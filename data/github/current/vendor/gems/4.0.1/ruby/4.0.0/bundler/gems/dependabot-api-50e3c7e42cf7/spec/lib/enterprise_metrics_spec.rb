# frozen_string_literal: true

require "rails_helper"
require "enterprise_metrics"

RSpec.describe EnterpriseMetrics do
  subject(:metrics) { described_class.instance }

  let(:statsd_client) { metrics.instance_variable_get(:@statsd) }

  describe "#count" do
    before do
      allow(statsd_client).to receive(:count)
    end

    it "sets the count to the given value" do
      metrics.count("my.count", 3)

      expect(statsd_client).to have_received(:count).with("my.count", 3)
    end

    it "appends allowed tags to the metric" do
      metrics.count("my.count", 3, tags: { error_type: "some_error" })

      expect(statsd_client).to have_received(:count).with("my.count.error_type:some_error", 3)
    end

    it "does not append tags that are not allow-listed" do
      metrics.count("my.count", 3, tags: { illegal_tag: "nope" })

      expect(statsd_client).to have_received(:count).with("my.count", 3)
    end

    it "appends allowed tags from array to the metric" do
      metrics.count("my.count", 3, tags: ["error_type:some_error"])

      expect(statsd_client).to have_received(:count).with("my.count.error_type:some_error", 3)
    end

    it "does not append tags that are not allow-listed from arrays" do
      metrics.count("my.count", 3, tags: ["illegal_tag:nope"])

      expect(statsd_client).to have_received(:count).with("my.count", 3)
    end
  end

  describe "#distribution" do
    before do
      allow(statsd_client).to receive(:timing)
    end

    it "fowards metrics to #timing" do
      time = 2.seconds.ago
      metrics.distribution("my.distribution", time)

      expect(statsd_client).to have_received(:timing).with("my.distribution", time)
    end
  end

  describe "#gauge" do
    before do
      allow(statsd_client).to receive(:gauge)
    end

    it "sets the gauge to the given value" do
      metrics.gauge("my.gauge", 3)

      expect(statsd_client).to have_received(:gauge).with("my.gauge", 3)
    end

    it "appends allowed tags to the metric" do
      metrics.gauge("my.gauge", 3, tags: { error_type: "some_error" })

      expect(statsd_client).to have_received(:gauge).with("my.gauge.error_type:some_error", 3)
    end

    it "does not append tags that are not allow-listed" do
      metrics.gauge("my.gauge", 3, tags: { illegal_tag: "nope" })

      expect(statsd_client).to have_received(:gauge).with("my.gauge", 3)
    end
  end

  describe "#histogram" do
    before do
      allow(statsd_client).to receive(:timing)
    end

    it "fowards metrics to #timing" do
      time = 2.seconds.ago
      metrics.histogram("my.histogram", time)

      expect(statsd_client).to have_received(:timing).with("my.histogram", time)
    end
  end

  describe "#increment" do
    before do
      allow(statsd_client).to receive(:increment)
    end

    it "increments the value" do
      metrics.increment("my.increment")

      expect(statsd_client).to have_received(:increment).with("my.increment")
    end

    it "appends allowed tags to the metric" do
      metrics.increment("my.increment", tags: { error_type: "some_error" })

      expect(statsd_client).to have_received(:increment).with("my.increment.error_type:some_error")
    end

    it "does not append tags that are not allow-listed" do
      metrics.increment("my.increment", tags: { illegal_tag: "nope" })

      expect(statsd_client).to have_received(:increment).with("my.increment")
    end
  end

  describe "#time" do
    before do
      allow(statsd_client).to receive(:time)
    end

    it "times the given block" do
      metrics.time("my.time") { "this block is timed" }

      expect(statsd_client).to have_received(:time).with("my.time")
    end

    it "appends allowed tags to the metric" do
      metrics.time("my.time", tags: { error_type: "some_error" }) { "this block is timed" }

      expect(statsd_client).to have_received(:time).with("my.time.error_type:some_error")
    end

    it "does not append tags that are not allow-listed" do
      metrics.time("my.time", tags: { illegal_tag: "nope" }) { "this block is timed" }

      expect(statsd_client).to have_received(:time).with("my.time")
    end
  end

  describe "#timing" do
    before do
      allow(statsd_client).to receive(:timing)
    end

    it "sets the timing to the given value" do
      time = 2.seconds.ago
      metrics.timing("my.timing", time)

      expect(statsd_client).to have_received(:timing).with("my.timing", time)
    end

    it "appends allowed tags to the metric" do
      time = 2.seconds.ago
      metrics.timing("my.timing", time, tags: { error_type: "some_error" })

      expect(statsd_client).to have_received(:timing).with("my.timing.error_type:some_error", time)
    end

    it "does not append tags that are not allow-listed" do
      time = 2.seconds.ago
      metrics.timing("my.timing", time, tags: { illegal_tag: "nope" })

      expect(statsd_client).to have_received(:timing).with("my.timing", time)
    end
  end

  describe "distribution_time" do
    before do
      allow(statsd_client).to receive(:timing)
    end

    it "delegates to statsd" do
      metric = "my_timeable_metric"

      expect(statsd_client).to receive(:timing).with(metric, 0)
      metrics.distribution_time(metric) { 1 + 1 }
    end

    it "returns the return value of the block passed" do
      metric = "my_timeable_metric"
      value = "value"

      expect(metrics.distribution_time(metric) { value }).to eq("value")
    end
  end

  describe "#close" do
    it "is callable" do
      expect { metrics.close }.not_to raise_error
    end
  end
end
