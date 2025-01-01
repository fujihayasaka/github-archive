# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../orca_test_helpers"

class OrcaHydroTest < GitHub::TestCase
  include OrcaTestHelpers

  fixtures do
    @pipeline_id = SecureRandom.uuid
  end

  context ".handle_message" do
    context "orca.v0.ModelDeploymentEvent" do
      test "delegates to the ModelDeploymentEvent handler" do
        value = {
          pipeline_id: @pipeline_id,
          status: :UNKNOWN,
          environment: "test",
        }

        handler = mock
        handler.expects(:handle)

        Orca::Hydro::ModelDeploymentEventHandler
          .expects(:new)
          .with(value)
          .returns(handler)

        Orca::Hydro.handle_message "orca.v0.ModelDeploymentEvent", value
      end
    end

    context "orca.v0.PipelineEvent" do
      test "delegates to the PipelineEvent handler" do
        value = {
          pipeline_id: @pipeline_id,
          organization_login: "github",
          status: :UNKNOWN,
          environment: "test",
        }

        handler = mock
        handler.expects(:handle)

        Orca::Hydro::PipelineEventHandler
          .expects(:new)
          .with(value)
          .returns(handler)

        Orca::Hydro.handle_message "orca.v0.PipelineEvent", value
      end
    end

    context "unknown topic" do
      test "does nothing" do
        Orca::Hydro::HANDLERS.each do |handler|
          handler.expects(:new).never
        end

        Orca::Hydro.handle_message "orca.v0.Unknown", {}
      end
    end
  end
end
