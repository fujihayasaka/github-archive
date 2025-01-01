# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../orca_test_helpers"

class OrcaHydroPipelineEventHandlerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include OrcaTestHelpers

  setup do
    HydroLoader.load_github
  end

  def handle(pipeline_event)
    organization = Organization.find_by(
      id: pipeline_event.organization.id
    ) || Organization.new(
      id: pipeline_event.organization.id,
      login: pipeline_event.organization.login,
    )

    pipeline = Orca::Pipeline.new(
      orca_pipeline_details(
        pipeline_id: pipeline_event.pipeline_id,
        organization: organization,
        repositories: [],
      )
    )

    Orca::Pipeline
      .stubs(:fetch_by_id)
      .with(pipeline_event.pipeline_id)
      .returns(pipeline)

    # Force the database connection to read-only, which is how the processor
    # works when started from bin/orca-processor (versus the test environment).
    ActiveRecord::Base.connected_to(role: :reading) do
      Orca::Hydro::PipelineEventHandler.new(pipeline_event.to_h).handle
    end
  end

  context "#handle" do
    %i[
      unknown
      enqueued
      started
      canceling
      canceled
      inactive
      deleting
      deleted
    ].each do |status|
      context "#{status}" do
        test "is ignored" do
          pipeline_event = build(:orca_pipeline_event, status)

          assert_no_difference -> { Orca::Model.count } do
            handle pipeline_event
          end

          assert_dogstats_increment 1, "github.orca.pipeline_event", tags: [
            "status:#{status}",
            "organization:true",
            "email_action:none",
          ]
        end
      end
    end

    context "completed" do
      test "sends a model_ready email" do
        pipeline_event = build(:orca_pipeline_event, :completed)

        CopilotOrcaMailer
          .expects(:model_ready)
          .with(pipeline_event.pipeline_id)
          .returns(mock(deliver_later: true))

        handle pipeline_event

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:completed
          organization:true
          email_action:model_ready
        ]
      end

      test "does nothing if the organization does not exist" do
        pipeline_event = build(:orca_pipeline_event, :completed)
        Organization.delete(pipeline_event.organization.id)

        CopilotOrcaMailer
          .expects(:model_ready)
          .never

        handle pipeline_event

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:completed
          organization:false
          email_action:none
        ]
      end
    end

    context "failed" do
      test "sends a model_failed email" do
        pipeline_event = build(:orca_pipeline_event, :failed)

        CopilotOrcaMailer
          .expects(:model_failed)
          .with(pipeline_event.pipeline_id)
          .returns(mock(deliver_later: true))

        handle pipeline_event

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:failed
          organization:true
          email_action:model_failed
        ]
      end

      test "does nothing if the organization does not exist" do
        pipeline_event = build(:orca_pipeline_event, :failed)
        Organization.delete(pipeline_event.organization.id)

        CopilotOrcaMailer
          .expects(:model_failed)
          .never

        handle pipeline_event

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:failed
          organization:false
          email_action:none
        ]
      end
    end
  end
end
