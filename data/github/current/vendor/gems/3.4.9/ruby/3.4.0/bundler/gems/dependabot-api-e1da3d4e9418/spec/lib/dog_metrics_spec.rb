# frozen_string_literal: true

require "rails_helper"
require "dog_metrics"

RSpec.describe DogMetrics do
  before do
    described_class.instance.close
    described_class.instance.increment("called to establish a connection")
  end

  describe "#count" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_metric"
      value = 1

      expect(statsd_client).to receive(:count).with(metric, value, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.count(metric, value)
    end
  end

  describe "#distribution" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_metric"
      value = 1

      expect(statsd_client).to receive(:distribution).with(metric, value, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.distribution(metric, value)
    end
  end

  describe "#gauge" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_metric"
      value = 1

      expect(statsd_client).to receive(:gauge).with(metric, value, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.gauge(metric, value)
    end
  end

  describe "#histogram" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_metric"
      value = 1

      expect(statsd_client).to receive(:histogram).with(metric, value, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.histogram(metric, value)
    end
  end

  describe "#timing" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_metric"
      value = 1

      expect(statsd_client).to receive(:timing).with(metric, value, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.timing(metric, value)
    end
  end

  describe "#increment" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_incrementable_metric"

      expect(statsd_client).to receive(:increment).with(metric, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.increment(metric)
    end
  end

  describe "#time" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_timeable_metric"

      expect(statsd_client).to receive(:time).with(metric, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.time(metric)
    end

    it "returns the return value of the block passed" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_timeable_metric"
      value = "value"

      allow(statsd_client).to receive(:time).
        with(metric, tags: []).
        and_return(value)
      allow(statsd_client).to receive(:flush)
      expect(instance.time(metric) { value }).to eq("value")
    end
  end

  describe "distribution_time" do
    it "delegates to statsd" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_timeable_metric"

      expect(statsd_client).to receive(:distribution).with(metric, 0, tags: [])
      expect(statsd_client).to receive(:flush)
      instance.distribution_time(metric) { 1 + 1 }
    end

    it "returns the return value of the block passed" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)
      metric = "my_timeable_metric"
      value = "value"

      allow(statsd_client).to receive(:distribution).
        with(metric, 0, tags: []).
        and_return(value)
      allow(statsd_client).to receive(:flush)
      expect(instance.distribution_time(metric) { value }).to eq("value")
    end
  end

  describe "#close" do
    it "closes the statsd connection" do
      instance = described_class.instance
      statsd_client = instance.instance_variable_get(:@dogstats)

      expect(statsd_client).to receive(:flush)
      expect(statsd_client).to receive(:close)
      instance.close
      expect(instance.instance_variable_get(:@dogstats)).to be_nil
    end
  end
end
