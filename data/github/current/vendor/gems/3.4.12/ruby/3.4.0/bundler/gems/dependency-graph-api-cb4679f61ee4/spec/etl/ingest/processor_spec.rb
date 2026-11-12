require "rails_helper"

module Ingest
  describe Processor do

    it "combines failbot_context from derived class" do
      class MyTestProcessor < Processor
        def initialize
          # we're cheating a little here and not super'ing processor because it does a bunch of config reading
        end

        def get_processor_specific_logging_context(hydro_message)
          return {
            strangely_stored_message: hydro_message
          }
        end
      end

      test_processor = MyTestProcessor.new
      hydro_message = Hydro::Source::Message.new(
        offset: 54321,
        topic: "sometopic",
        key: "somekey",
        partition: "somepartition",
        value: {})
      logging_context = test_processor.get_logging_context(hydro_message)

      expect(logging_context[:strangely_stored_message]).to eq hydro_message
      expect(logging_context["gh.hydro.msg.offset"]).to eq 54321
      expect(logging_context["gh.hydro.msg.topic"]).to eq "sometopic"
      expect(logging_context["gh.hydro.msg.key"]).to eq "somekey"
      expect(logging_context["gh.hydro.msg.partition"]).to eq "somepartition"
    end
  end
end
