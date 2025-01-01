# typed: false
# frozen_string_literal: true

require "test_helper"

class OrcaHydroStreamProcessorTest < GitHub::TestCase
  include HydroTestHelpers

  test "it delegates to Orca::Hydro.handle_message" do
    pipeline_event = build(:orca_pipeline_event)
    message = pipeline_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .with("orca.v0.PipelineEvent", message)
      .once

    hydro_publisher.publish(message, schema: "orca.v0.PipelineEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end

  test "it ignores messages in other environments" do
    pipeline_event = build(:orca_pipeline_event, environment: "staging")
    message = pipeline_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .never

    hydro_publisher.publish(message, schema: "orca.v0.PipelineEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end

  test "it processes messages without an environment" do
    pipeline_event = build(:orca_pipeline_event, environment: "")
    message = pipeline_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .with("orca.v0.PipelineEvent", message)
      .once

    hydro_publisher.publish(message, schema: "orca.v0.PipelineEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end
end
