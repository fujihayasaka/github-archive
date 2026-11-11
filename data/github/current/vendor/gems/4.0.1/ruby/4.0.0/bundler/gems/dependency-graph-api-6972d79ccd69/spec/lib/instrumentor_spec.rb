require "instrumentor"
require "rails_helper"

describe Instrumentor do
  describe ".count" do
    before(:each) do
      allow(Rails.application.stats).to receive(:count).and_call_original
    end

    it "sends count to statsd" do
      subject.count("my.stat.here", 12, foo: "bar", baz: "qux")
      expect(stats).to have_received(:count).with("my.stat.here", 12, tags: ["foo:bar", "baz:qux"])
    end
  end

   describe ".histogram" do
    before(:each) do
      allow(Rails.application.stats).to receive(:histogram).and_call_original
    end

    it "sends histogram to statsd" do
      subject.histogram("my.stat.here", 12, foo: "bar", baz: "qux")
      expect(stats).to have_received(:histogram).with("my.stat.here", 12, tags: ["foo:bar", "baz:qux"])
    end
   end

  describe ".increment" do
    before(:each) do
      allow(Rails.application.stats).to receive(:increment).and_call_original
    end

    it "sends increment to statsd" do
      subject.increment("my.stat.here", foo: "bar", baz: "qux")
      expect(stats).to have_received(:increment).with("my.stat.here", tags: ["foo:bar", "baz:qux"])
    end
  end

  describe ".time" do
    before(:each) do
      allow(Rails.application.stats).to receive(:time).and_call_original
    end

    it "sends time to statsd" do
      expect do
        subject.time("my.stat.here", foo: "bar", baz: "qux") do
          raise StandardError
        end
        # test that an error was raised to make sure block is called
      end.to raise_error(StandardError)
      expect(Rails.application.stats).to have_received(:time).with("my.stat.here", tags: ["foo:bar", "baz:qux"])
    end
  end

  describe ".time_dist" do
    before(:each) do
      allow(Rails.application.stats).to receive(:distribution).and_call_original
    end

    it "sends time distribution to statsd with block" do
      expect do
        subject.time_dist("my.stat.here", foo: "bar", baz: "qux") do
          raise StandardError
        end
        # test that an error was raised to make sure block is called
      end.to raise_error(StandardError)
      expect(Rails.application.stats).to have_received(:distribution).with("my.stat.here", kind_of(Numeric), tags: ["foo:bar", "baz:qux"])
    end
  end
end
