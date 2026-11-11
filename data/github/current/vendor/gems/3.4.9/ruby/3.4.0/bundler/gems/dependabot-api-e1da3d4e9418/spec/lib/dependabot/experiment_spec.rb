# frozen_string_literal: true

require "rails_helper"
require "dependabot/experiment"

RSpec.describe Dependabot::Experiment do
  let(:redis) { Dependabot.redis }

  before do
    redis.flushdb
    Dependabot::Exceptions.reset!

    allow(Failbot).to receive(:push).and_call_original
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow(MetricsClient).to receive(:increment)

    allow(Dependabot::Logger).to receive(:info)
  end

  describe "#cleanup" do
    let(:experiment) do
      described_class.new("cleanup-test") do |experiment|
        experiment.use { "foo" }
        experiment.try { "bar" }
      end
    end

    let(:redis_config_key) do
      "science.cleanup_test.config.sample_rate"
    end

    before do
      redis.set(redis_config_key, 100)
      experiment.run

      # The experiment is enabled
      expect(experiment).to be_enabled
      expect(experiment.current_sample_rate).to be(100)

      # And we have a mismatch in redis
      expect(redis.llen(experiment.mismatch_redis_key)).to eq 1
    end

    it "removes only the configuration, leaving mismatch data intact" do
      expect { experiment.cleanup }.
        to change { redis.exists?(redis_config_key) }.from(true).to(false)

      expect(redis.llen(experiment.mismatch_redis_key)).to eq 1
    end

    it "is idempotent" do
      experiment.cleanup
      expect { experiment.cleanup }.not_to raise_error
    end

    it "the bang method removes mismatch data as well" do
      expect { experiment.cleanup! }.
        to change { redis.exists?(experiment.mismatch_redis_key) }.from(true).to(false)

      expect(redis.exists?(redis_config_key)).to be false
    end
  end

  describe "#sample_rate" do
    let(:experiment) do
      described_class.new("sample-rate-test")
    end

    let(:redis_config_key) do
      "science.sample_rate_test.config.sample_rate"
    end

    context "not set" do
      it "defaults to 0" do
        expect(experiment.current_sample_rate).to be_zero
      end

      it "disables the experiment by default" do
        expect(experiment).not_to be_enabled
      end
    end

    context "set in redis" do
      before { redis.set(redis_config_key, 50) }

      it "is retrieved from redis" do
        expect(experiment.current_sample_rate).to be(50)
      end
    end

    it "persists the value to redis" do
      expect { experiment.sample_rate(42) }.
        to change { redis.get(redis_config_key) }.from(nil).to("42")
    end

    it "changes the value in memory for the current instance" do
      expect { experiment.sample_rate(42) }.
        to change(experiment, :current_sample_rate).from(0).to(42)
    end

    it "is picked up by subsequent instances with the same name" do
      experiment.sample_rate(42)

      expect(described_class.new("sample-rate-test").current_sample_rate).
        to be(42)
    end

    it "is not picked up by subsequent instances a different name" do
      experiment.sample_rate(42)

      expect(described_class.new("sample-rate-test-v2").current_sample_rate).
        to be(0)
    end

    it "may be set to 0% to disable the experiment" do
      experiment.sample_rate 0

      expect(experiment).not_to be_enabled
    end

    it "may be set to 100% to fully enable the experiment" do
      experiment.sample_rate 100

      expect(experiment).to be_enabled
    end

    it "may not be set to a negative value" do
      expect { experiment.sample_rate(-1) }.to raise_error(ArgumentError)
    end

    it "may not exceed 100%" do
      expect { experiment.sample_rate(101) }.to raise_error(ArgumentError)
    end

    it "may not be set to a string" do
      expect { experiment.sample_rate("50%") }.to raise_error(ArgumentError)
    end

    it "may not be set to a real number" do
      expect { experiment.sample_rate(0.5) }.to raise_error(ArgumentError)
    end
  end

  describe "#slug" do
    subject { experiment.slug }

    let(:experiment) { described_class.new(name) }

    context "a humanized name" do
      let(:name) { "My Awesome Experiment" }

      it { is_expected.to eql "my_awesome_experiment" }
    end

    context "a hyphenated name" do
      let(:name) { "my-awesome-experiment" }

      it { is_expected.to eql "my_awesome_experiment" }
    end

    context "a snake case name name" do
      let(:name) { "my_awesome_experiment" }

      it { is_expected.to eql "my_awesome_experiment" }
    end
  end

  describe "#metric_tags" do
    let(:experiment) do
      described_class.new "same" do |experiment|
        experiment.sample_rate 100
        experiment.context user_id: 5
        experiment.metric_tags = { account_type: "user" }

        experiment.use { 4 }
        experiment.try { 4 }
      end
    end

    it "is passed unto instrumentation" do
      experiment.run

      expect(MetricsClient).
        to have_received(:timing).
        with("science.control",
             anything,
             tags: {
               experiment: "same",
               account_type: "user",
             })

      expect(MetricsClient).
        to have_received(:timing).
        with("science.candidate",
             anything,
             tags: {
               experiment: "same",
               account_type: "user",
             })

      expect(MetricsClient).
        to have_received(:increment).
        with("science.matched",
             tags: {
               experiment: "same",
               account_type: "user",
             })
    end
  end

  describe "a mismatched result" do
    let(:experiment) do
      described_class.new "string-to-int" do |experiment|
        experiment.sample_rate 100
        experiment.context user_id: 5

        experiment.use { 4 }
        experiment.try { "4" }
      end
    end

    it "returns the control value" do
      expect(experiment.run).to be(4)
    end

    it "instruments the experiment" do
      experiment.run

      expect(MetricsClient).
        to have_received(:gauge).
        with("science.sample_rate",
             100,
             tags: {
               experiment: "string_to_int",
             })

      expect(MetricsClient).
        to have_received(:timing).
        with("science.control",
             anything,
             tags: {
               experiment: "string_to_int",
             })

      expect(MetricsClient).
        to have_received(:timing).
        with("science.candidate",
             anything,
             tags: {
               experiment: "string_to_int",
             })

      expect(MetricsClient).
        to have_received(:increment).
        with("science.mismatched",
             tags: {
               experiment: "string_to_int",
             })
    end

    it "logs the mismatch" do
      experiment.run

      expect(Dependabot::Logger).
        to have_received(:info).with(
          msg: "Mismatch found in experiment 'string-to-int'",
          experiment: "string_to_int",
          context: { user_id: 5 },
          control: { value: 4 },
          candidate: { value: "4" },
          execution_order: anything,
          experiment_exceptions: []
        )
    end

    it "writes the mismatch to Redis" do
      expect(redis.llen(experiment.mismatch_redis_key)).to eq 0

      experiment.run

      expect(redis.llen(experiment.mismatch_redis_key)).to eq 1

      results = JSON.parse(redis.lindex(experiment.mismatch_redis_key, 0),
                           { symbolize_names: true })

      expect(results[:experiment]).to eql("string_to_int")
      expect(results[:context]).to eql({ user_id: 5 })
      expect(results[:control]).to eql({ value: 4 })
      expect(results[:candidate]).to eql({ value: "4" })
      expect(results[:execution_order]).
        to contain_exactly("control", "candidate")
      expect(results[:experiment_exceptions]).to be_empty
    end

    context "when store_mismatches is false" do
      before do
        experiment.store_mismatches = false
      end

      it "does not write anything to Redis" do
        expect(redis.llen(experiment.mismatch_redis_key)).to eq 0

        experiment.run

        expect(redis.llen(experiment.mismatch_redis_key)).to eq 0
      end
    end
  end

  describe "a matched result" do
    let(:experiment) do
      described_class.new "string-to-string" do |experiment|
        experiment.sample_rate 100
        experiment.context user_id: 5

        experiment.use { 4 }
        experiment.try { "4" }

        experiment.compare do |control, candidate|
          control.to_s == candidate.to_s
        end
      end
    end

    it "returns the control value" do
      expect(experiment.run).to be(4)
    end

    it "instruments the experiment" do
      experiment.run

      expect(MetricsClient).
        to have_received(:gauge).
        with("science.sample_rate",
             100,
             tags: {
               experiment: "string_to_string",
             })

      expect(MetricsClient).
        to have_received(:timing).
        with("science.control",
             anything,
             tags: {
               experiment: "string_to_string",
             })

      expect(MetricsClient).
        to have_received(:timing).
        with("science.candidate",
             anything,
             tags: {
               experiment: "string_to_string",
             })

      expect(MetricsClient).
        to have_received(:increment).
        with("science.matched",
             tags: {
               experiment: "string_to_string",
             })
    end
  end

  describe "an exception in the control" do
    let(:experiment) do
      described_class.new "control-goes-bang" do |experiment|
        experiment.sample_rate 100
        experiment.context user_id: 5

        experiment.use { raise "bang!" }
        experiment.try { "4" }
      end
    end

    it "re-raises" do
      expect { experiment.run }.to raise_error(RuntimeError, "bang!")
    end

    it "counts it as a mismatch" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(MetricsClient).
        to have_received(:increment).
        with("science.mismatched",
             tags: {
               experiment: "control_goes_bang",
             })
    end

    it "logs details about the exception for the control" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(Dependabot::Logger).
        to have_received(:info).with(
          msg: "Mismatch found in experiment 'control-goes-bang'",
          experiment: "control_goes_bang",
          context: { user_id: 5 },
          control: {
            exception: RuntimeError,
            message: "bang!",
            backtrace: anything,
          },
          candidate: { value: "4" },
          execution_order: anything,
          experiment_exceptions: []
        )
    end
  end

  describe "an exception in a candidate" do
    let(:experiment) do
      described_class.new "candidate-goes-bang" do |experiment|
        experiment.sample_rate 100
        experiment.context user_id: 5

        experiment.use { 4 }
        experiment.try { raise "bang!" }
      end
    end

    it "returns the control" do
      expect { experiment.run }.not_to raise_error
      expect(experiment.run).to be(4)
    end

    it "counts it as a mismatch" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(MetricsClient).
        to have_received(:increment).
        with("science.mismatched",
             tags: {
               experiment: "candidate_goes_bang",
             })
    end

    it "logs details about the exception for the candidate" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(Dependabot::Logger).
        to have_received(:info).with(
          msg: "Mismatch found in experiment 'candidate-goes-bang'",
          experiment: "candidate_goes_bang",
          context: { user_id: 5 },
          control: { value: 4 },
          candidate: {
            exception: RuntimeError,
            message: "bang!",
            backtrace: anything,
          },
          execution_order: anything,
          experiment_exceptions: []
        )
    end
  end

  describe "an exception in the comparison" do
    let(:comparison_error) do
      RuntimeError.new("bang!")
    end

    let(:experiment) do
      described_class.new "comparison-goes-bang" do |experiment|
        experiment.sample_rate 100
        experiment.context "gh.owner.id": 5

        experiment.use { 4 }
        experiment.try { "4" }

        experiment.compare { raise comparison_error }
      end
    end

    it "returns the control" do
      expect { experiment.run }.not_to raise_error
      expect(experiment.run).to be(4)
    end

    it "counts it as a mismatch" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(MetricsClient).
        to have_received(:increment).
        with("science.mismatched",
             tags: {
               experiment: "comparison_goes_bang",
             })
    end

    it "logs details about the exception in the context" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(Dependabot::Logger).
        to have_received(:info).with(
          msg: "Mismatch found in experiment 'comparison-goes-bang'",
          experiment: "comparison_goes_bang",
          context: {
            "gh.owner.id": 5,
          },
          control: { value: 4 },
          candidate: { value: "4" },
          execution_order: anything,
          experiment_exceptions: [
            {
              operation: :compare,
              exception: RuntimeError,
              message: "bang!",
              backtrace: anything,
            },
          ]
        )
    end

    it "forwards the error to failbot" do
      begin
        experiment.run
      rescue StandardError
        nil
      end

      expect(Failbot).to have_received(:push).
        with("gh.dependabot_api.experiment.slug": "comparison_goes_bang",
             "gh.dependabot_api.experiment.operation": :compare,
             "#gh.owner.id": 5)

      expect(Failbot).to have_received(:report).with(comparison_error, {})
    end
  end
end
