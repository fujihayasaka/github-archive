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
    [:unknown, :enqueued, :started, :canceling, :canceled].each do |status|
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
            "model_action:none",
          ]
        end
      end
    end

    context "failed" do
      test "sends a model_failed email" do
        pipeline_event = build(:orca_pipeline_event, :failed)

        assert_no_difference -> { Orca::Model.count } do
          handle pipeline_event
        end

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:failed
          organization:true
          email_action:model_failed
          model_action:none
        ]
      end
    end

    context "completed" do
      test "creates a model" do
        org = create(:organization)
        pipeline_event = build(:orca_pipeline_event, :completed, org: org)

        assert_difference -> { Orca::Model.count }, 1 do
          handle pipeline_event
        end

        model = Orca::Model.find_by!(pipeline_id: pipeline_event.pipeline_id)
        assert_equal pipeline_event.model.resource, model.resource,
          "sets the resource"
        assert_equal pipeline_event.model.deployment, model.deployment,
          "sets the deployment"
        assert_equal org, model.organization,
          "associates the model with the organization"

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:completed
          organization:true
          email_action:model_ready
          model_action:create
        ]
      end

      test "updates an existing model" do
        org = create(:organization)
        pipeline_event = build(:orca_pipeline_event, :completed, org: org)

        Orca::Model.create(
          pipeline_id: pipeline_event.pipeline_id,
          organization: org,
          resource: "old resource",
          deployment: "old deployment",
        )

        assert_no_difference -> { Orca::Model.count } do
          handle pipeline_event
        end

        model = Orca::Model.find_by!(pipeline_id: pipeline_event.pipeline_id)
        assert_equal pipeline_event.model.resource, model.resource,
          "updates the resource"
        assert_equal pipeline_event.model.deployment, model.deployment,
          "updates the deployment"

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:completed
          organization:true
          email_action:model_ready
          model_action:update
        ]
      end

      test "does not change the organization for an existing model" do
        pipeline_event = build(:orca_pipeline_event, :completed)

        old_org = create(:organization)
        Orca::Model.create(
          pipeline_id: pipeline_event.pipeline_id,
          organization: old_org,
          resource: "old resource",
          deployment: "old deployment",
        )

        assert_no_difference -> { Orca::Model.count } do
          handle pipeline_event
        end

        model = Orca::Model.find_by!(pipeline_id: pipeline_event.pipeline_id)
        assert_equal old_org, model.organization,
          "does not change the organization"
      end

      test "does nothing if the resource is empty" do
        pipeline_event = build(:orca_pipeline_event, :completed, resource: "")

        assert_no_difference -> { Orca::Model.count } do
          assert_raises Orca::Hydro::PipelineEventHandler::Error do
            handle pipeline_event
          end
        end
      end

      test "does nothing if the deployment is empty" do
        pipeline_event = build(:orca_pipeline_event, :completed, deployment: "")

        assert_no_difference -> { Orca::Model.count } do
          assert_raises Orca::Hydro::PipelineEventHandler::Error do
            handle pipeline_event
          end
        end
      end

      test "does nothing if the organization does not exist" do
        pipeline_event = build(:orca_pipeline_event, :completed)
        Organization.delete(pipeline_event.organization.id)

        assert_no_difference -> { Orca::Model.count } do
          handle pipeline_event
        end

        assert_dogstats_increment 1, "github.orca.pipeline_event", tags: %w[
          status:completed
          organization:false
          email_action:none
          model_action:none
        ]
      end
    end

    [:inactive, :deleting, :deleted].each do |status|
      context "#{status}" do
        test "deletes existing model" do
          pipeline_event = build(:orca_pipeline_event, status)
          model = create(:orca_model, pipeline_id: pipeline_event.pipeline_id)

          assert_difference -> { Orca::Model.count }, -1 do
            handle pipeline_event
          end

          refute Orca::Model.exists?(model.id),
            "deletes the model"

          assert_dogstats_increment 1, "github.orca.pipeline_event", tags: [
            "status:#{status}",
            "organization:true",
            "email_action:none",
            "model_action:delete",
          ]
        end

        test "does nothing if the model does not exist" do
          pipeline_event = build(:orca_pipeline_event, status)

          assert_no_difference -> { Orca::Model.count } do
            handle pipeline_event
          end

          assert_dogstats_increment 1, "github.orca.pipeline_event", tags: [
            "status:#{status}",
            "organization:true",
            "email_action:none",
            "model_action:none",
          ]
        end
      end
    end
  end
end
