# typed: true
# frozen_string_literal: true

require "test_helper"

class OrcaHydroStreamProcessorTest < GitHub::TestCase
  include HydroTestHelpers

  test "it delegates to Orca::Hydro.handle_message" do
    model_deployment_event = build(:orca_model_deployment_event)
    message = model_deployment_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .with("orca.v0.ModelDeploymentEvent", message)
      .once

    hydro_publisher.publish(message, schema: "orca.v0.ModelDeploymentEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end

  test "it ignores messages in other environments" do
    model_deployment_event = build(
      :orca_model_deployment_event,
      environment: "staging",
    )
    message = model_deployment_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .never

    hydro_publisher.publish(message, schema: "orca.v0.ModelDeploymentEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end

  test "it processes messages without an environment" do
    model_deployment_event = build(
      :orca_model_deployment_event,
      environment: "",
    )
    message = model_deployment_event.to_h

    Orca::Hydro
      .expects(:handle_message)
      .with("orca.v0.ModelDeploymentEvent", message)
      .once

    hydro_publisher.publish(message, schema: "orca.v0.ModelDeploymentEvent")

    run_processor(Orca::Hydro::StreamProcessor.new)
  end
end
