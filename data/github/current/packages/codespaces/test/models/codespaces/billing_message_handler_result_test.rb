# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::BillingMessageHandlerResultTest < GitHub::TestCase
  context "#publish" do
    context "when publisher is PUBLISH_RETRIER" do
      test "calls PublishRetrier when passed PUBLISH_RETRIER" do
        topic = "topic"
        data = "data"
        result = Codespaces::BillingMessageHandlerResult.new(hydro_topic: topic, hydro_payload: data, publisher: Codespaces::BillingMessageHandlerResult::PUBLISH_RETRIER)
        Hydro::PublishRetrier.expects(:publish).with(data, schema: topic).returns(stub(error: false))
        result.publish
      end

      test "calls PublishRetrier when passed PUBLISH_RETRIER and logs error" do
        topic = "topic"
        data = "data"
        result = Codespaces::BillingMessageHandlerResult.new(hydro_topic: topic, hydro_payload: data, publisher: Codespaces::BillingMessageHandlerResult::PUBLISH_RETRIER)
        GitHub.logger.expects(:error).with("Failed to publish usage message to billing platform", { hydro_topic: topic })
        Hydro::PublishRetrier.expects(:publish).with(data, schema: topic).returns(stub(error: true))
        result.publish
      end
    end

    test "calls GlobalInstrumenter when passed anything else" do
      topic = "topic"
      data = "data"
      result = Codespaces::BillingMessageHandlerResult.new(hydro_topic: topic, hydro_payload: data, publisher: "banana")
      GlobalInstrumenter.expects(:instrument).with(topic, data)
      result.publish
    end
  end
end
