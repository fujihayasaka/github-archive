# typed: true
# frozen_string_literal: true

require "test_helper"

class Api::InstrumentSegmentTest < GitHub::TestCase
  setup do
    @env = {
      "REQUEST_METHOD" => "ZING",
      "process.api.controller" => "Some::App",
    }
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "it instruments blocks with .call" do
    tags = []
    Api::InstrumentSegment.call(@env, "api.test_segment", tags: tags) do
      tags << "late:tag"
    end

    operation = GitHub.dogstats.operations.find { |o| o.stat.start_with?("api.") }
    assert_equal "api.test_segment", operation.stat
    assert_equal ["late:tag", "http_method:ZING", "api_app:Some::App"], operation.tags.to_a
  end

  test "it begins and ends segments" do
    refute Api::InstrumentSegment.active?(@env, "api.test_segment")

    Api::InstrumentSegment.begin_segment(@env, "api.test_segment")
    assert_nil GitHub.dogstats.operations.find { |o| o.stat.start_with?("api.") }
    assert Api::InstrumentSegment.active?(@env, "api.test_segment")

    Api::InstrumentSegment.end_segment(@env, "api.test_segment")
    refute Api::InstrumentSegment.active?(@env, "api.test_segment")

    operation = GitHub.dogstats.operations.find { |o| o.stat.start_with?("api.") }
    assert_equal "api.test_segment", operation.stat
  end

  test "it requires segments to be started before they're ended" do
    Api::InstrumentSegment.begin_segment(@env, "api.test_segment")
    err = assert_raises Api::InstrumentSegment::SegmentStateError do
      Api::InstrumentSegment.end_segment(@env, "api.broken_segment")
    end

    expected_message = 'Can\'t end un-started segment: "api.broken_segment" (active segments: ["api.test_segment"]))'
    assert_equal expected_message, err.message

    # No stats are recorded
    assert_nil GitHub.dogstats.operations.find { |o| o.stat.start_with?("api.") }
  end


  test "it is hooked up to Routers::Api" do
    example_app = ->(_env) { :was_called }
    example_router = GitHub::Routers::Api.new(example_app)
    example_router.expects(:select_app_without_instrumentation).with do |env|
      env["process.api.controller"] = "Router::Test"
    end.returns(example_app)

    dummy_env = {
      "PATH_INFO" => "/",
      "SERVER_NAME" => "api.github.com",
      "REQUEST_METHOD" => "SPOOF",
    }

    assert_equal :was_called, example_router.call(dummy_env)
  end
end
