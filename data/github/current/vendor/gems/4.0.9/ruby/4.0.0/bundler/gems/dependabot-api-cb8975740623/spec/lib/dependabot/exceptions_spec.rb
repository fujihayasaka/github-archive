# frozen_string_literal: true

require "rails_helper"
require "dependabot/exceptions"
require "trilogy"
require "hydro"

RSpec.describe Dependabot::Exceptions do
  let(:production) { false }

  before do
    Failbot.reset!
    Failbot.setup(
      { "FAILBOT_BACKEND" => "memory" }, { "shared" => "Default Context" }
    )
    described_class.reset!
    mock_env = OpenStruct.new(production?: production)
    allow(Rails).to receive(:env).and_return(mock_env)
  end

  after :all do # rubocop:disable RSpec/BeforeAfterAll
    # Prevent exception context from leaking outside of this suite
    described_class.reset!
  end

  context "accepted error" do
    let(:error) { StandardError.new("kaboom") }

    it "forwards exceptions" do
      expect(Failbot).
        to receive(:report).with(error, {})
      described_class.report(error)
    end

    it "forwards extra" do
      extra = { "gh.actor.id": 555 }
      expect(Failbot).
        to receive(:report).with(error, extra)
      described_class.report(error, extra)
    end

    it "increments the reported_exceptions metric" do
      expect(MetricsClient).
        to receive(:increment).with("reported_exceptions",
                                    tags: { exception_class: "StandardError" })
      described_class.report(error)
    end

    it "increments the reported_exceptions metric with report!" do
      expect(MetricsClient).
        to receive(:increment).with("reported_exceptions",
                                    tags: { exception_class: "StandardError" })
      described_class.report!(error)
    end

    context "with pushed context" do
      before do
        allow(Failbot).
          to receive(:push).and_call_original
        allow(Failbot).
          to receive(:report)
      end

      it "forwards" do
        described_class.push({ "gh.actor.id": 1 })
        described_class.push({ "gh.actor.id": 2 })
        described_class.report(error, {})

        expect(Failbot).
          to have_received(:push).with({ "gh.actor.id": 1 }).ordered
        expect(Failbot).
          to have_received(:push).with({ "gh.actor.id": 2 }).ordered
        expect(Failbot).
          to have_received(:report).with(error, {})
      end

      it "forwards in blocks" do
        described_class.push({ "gh.actor.id": 1 }) { described_class.report(error, {}) }
        described_class.push({ "gh.actor.id": 2 }) { described_class.report(error, {}) }

        expect(Failbot).
          to have_received(:push).with({ "gh.actor.id": 1 })
        expect(Failbot).
          to have_received(:push).with({ "gh.actor.id": 2 })
        expect(Failbot).
          to have_received(:report).with(error, {}).exactly(2).times
      end

      it "doesn't include context from another thread" do
        Thread.new do
          described_class.push({ "gh.actor.id": 1234 })
        end.join

        described_class.push({ "gh.actor.id": 4321 })

        # Failbot's thread-local context isolates each thread's pushes
        expect(described_class.context.any? { |c| c[:"gh.actor.id"] == 4321 }).to be true
        expect(described_class.context.none? { |c| c[:"gh.actor.id"] == 1234 }).to be true
      end

      it "indexes special tags" do
        described_class.push({ "gh.repo.id": 1234, "gh.aqueduct.queue.name": 7 }) { described_class.report(error, {}) }

        expect(Failbot).
          to have_received(:push).with({ "#gh.repo.id": 1234, "gh.aqueduct.queue.name": 7 })
      end
    end

    it "allows resetting context" do
      allow(Failbot).
        to receive(:report)

      described_class.push({ "gh.repo.id": 1234 })
      described_class.reset!
      described_class.report(error, {})

      expect(Failbot).
        to have_received(:report).with(error, {})
    end
  end

  context "telemetry attribute validation" do
    let(:error) { StandardError.new("kaboom") }

    it "raises when an unknown telemetry attribute is pushed when not production" do
      expect { described_class.push({ "my.new.key": 1 }) }.to raise_error(/my.new.key/)
    end

    it "raises when an unknown telemetry attribute is reported when not production" do
      expect { described_class.report(error, { "my.new.key": 1 }) }.to raise_error(/my.new.key/)
    end

    context "in production" do
      let(:production) { true }

      it "allows unknown telemetry attribute when pushed" do
        allow(Failbot).to receive(:push)
        allow(Failbot).to receive(:report)

        described_class.push({ "my.new.key": 1 })
        described_class.report(error)

        expect(Failbot).to have_received(:push).with({ "my.new.key": 1 })
      end

      it "allows unknown telemetry attribute when reported" do
        allow(Failbot).to receive(:push)
        allow(Failbot).to receive(:report)

        described_class.report(error, { "my.new.key": 1 })

        expect(Failbot).to have_received(:report).with(error, { "my.new.key": 1 })
      end
    end
  end

  context "updater errors" do
    it "reports with an alternate app name" do
      error_details = { "error-message" => "kaboom" }
      error = UpdaterError.new(error_details)

      expect(Failbot).
        to receive(:report).
        with(error, { app: described_class::UPDATER_FAILBOT_APP_NAME })

      described_class.report(error)
    end

    it "increments the updater_errors metric" do
      error_class = "MyUpdaterError"
      error_details = { "error-class" => error_class }
      error = UpdaterError.new(error_details)

      expect(MetricsClient).
        to receive(:increment).
        with("updater_errors", tags: { exception_class: error_class })

      described_class.report(error)
    end

    it "does not increment the reported_exceptions metric" do
      error = UpdaterError.new({ "error-class" => "MyUpdaterError" })

      expect(MetricsClient).
        not_to receive(:increment).
        with("reported_exceptions", anything)

      described_class.report(error)
    end
  end
end
