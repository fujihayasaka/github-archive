# frozen_string_literal: true

require "rails_helper"

RSpec.describe Activity::Logger do
  let(:activity_log) do
    described_class.new
  end

  before do
    allow(Dependabot::Logger).to receive(:info)
    allow(Dependabot::Logger).to receive(:log_context).and_call_original
    allow(Activity::PauseManager).to receive(:handle_activity_log_event)
  end

  describe "#record_event" do
    it "writes a structured info log of the event to the global topic" do
      activity_log.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "system.event-a",
          foo: "bar",
        }
      )
    end

    it "sets the log context to 'system'" do
      activity_log.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:log_context).with(
        {
          context: "system",
        }
      )
    end

    it "notifys the RepositoryActivityMonitor of the event" do
      activity_log.record_event("event-a", tags: { foo: "bar" })

      expect(Activity::PauseManager).to have_received(:handle_activity_log_event).with(
        "system.event-a",
        {
          context: "system",
          foo: "bar",
        }
      )
    end

    it "converts the event name to snake-case" do
      activity_log.record_event("event A")

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "system.event-a",
        }
      )
    end

    it "replaces underscores with dashes" do
      activity_log.record_event("event_a")

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "system.event-a",
        }
      )
    end

    it "leaves any periods unmodified" do
      activity_log.record_event("event.a")

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "system.event.a",
        }
      )
    end

    it "raises an error if any tags overwrite the defaults" do
      expect { activity_log.record_event("event-a", tags: { context: "random" }) }.
        to raise_error(ArgumentError, "The tag 'context' would overwrite defaults")

      expect { activity_log.record_event("event-a", tags: { activity_log_event: "event-b", context: "random" }) }.
        to raise_error(ArgumentError, "The tags 'activity_log_event, context' would overwrite defaults")
    end

    it "does not raise errors in production" do
      mock_env = OpenStruct.new(production?: true)
      allow(Rails).to receive(:env).and_return(mock_env)

      expect { activity_log.record_event("event-a", tags: { context: "random" }) }.
        not_to raise_error
    end
  end
end
