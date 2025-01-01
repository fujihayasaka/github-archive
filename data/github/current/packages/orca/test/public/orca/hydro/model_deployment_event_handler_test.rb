# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../orca_test_helpers"

class OrcaHydroModelDeploymentEventHandlerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include OrcaTestHelpers

  setup do
    HydroLoader.load_github
  end

  def handle(event)
    organization = Organization.find_by(
      id: event.organization.id
    ) || Organization.new(
      id: event.organization.id,
      login: event.organization.login,
    )

    pipeline = Orca::Pipeline.new(
      orca_pipeline_details(
        pipeline_id: event.pipeline_id,
        organization: organization,
        repositories: [],
      )
    )

    Orca::Pipeline
      .stubs(:fetch_by_id)
      .with(event.pipeline_id)
      .returns(pipeline)

    # Force the database connection to read-only, which is how the processor
    # works when started from bin/orca-processor (versus the test environment).
    ActiveRecord::Base.connected_to(role: :reading) do
      Orca::Hydro::ModelDeploymentEventHandler.new(event.to_h).handle
    end
  end

  context "#handle" do
    context "unknown" do
      test "is ignored" do
        event = build(:orca_model_deployment_event)

        assert_no_difference -> { Orca::Model.count } do
          handle event
        end

        assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
          "status:unknown",
          "usage:unknown",
          "organization:true",
          "model_action:none",
        ]
      end
    end

    context "active" do
      context "unknown usage" do
        test "is ignored" do
          event = build(:orca_model_deployment_event, :active)

          assert_no_difference -> { Orca::Model.count } do
            handle event
          end

          assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
            "status:active",
            "usage:unknown",
            "organization:true",
            "model_action:none",
          ]
        end
      end

      context "gating" do
        test "is ignored" do
          event = build(:orca_model_deployment_event, :active, :gating)

          assert_no_difference -> { Orca::Model.count } do
            handle event
          end

          assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
            "status:active",
            "usage:gating",
            "organization:true",
            "model_action:none",
          ]
        end
      end

      context "inference" do
        test "creates a model" do
          org = create(:organization)
          event = build(:orca_model_deployment_event, :active, :inference, org: org)

          assert_difference -> { Orca::Model.count }, 1 do
            handle event
          end

          pipeline_id = event.pipeline_id
          model = Orca::Model.find_by!(pipeline_id: pipeline_id)
          assert_equal event.resource, model.resource,
            "sets the resource"
          assert_equal event.deployment, model.deployment,
            "sets the deployment"
          assert_equal org, model.organization,
            "associates the model with the organization"

          assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: %w[
            status:active
            organization:true
            model_action:create
          ]
        end

        test "updates an existing model" do
          org = create(:organization)
          event = build(:orca_model_deployment_event, :active, :inference, org: org)

          Orca::Model.create(
            pipeline_id: event.pipeline_id,
            organization: org,
            resource: "old resource",
            deployment: "old deployment",
          )

          assert_no_difference -> { Orca::Model.count } do
            handle event
          end

          model = Orca::Model.find_by!(pipeline_id: event.pipeline_id)
          assert_equal event.resource, model.resource,
            "updates the resource"
          assert_equal event.deployment, model.deployment,
            "updates the deployment"

          assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: %w[
            status:active
            usage:inference
            organization:true
            model_action:update
          ]
        end

        test "does not change the organization for an existing model" do
          event = build(:orca_model_deployment_event, :active, :inference)

          old_org = create(:organization)
          Orca::Model.create(
            pipeline_id: event.pipeline_id,
            organization: old_org,
            resource: "old resource",
            deployment: "old deployment",
          )

          assert_no_difference -> { Orca::Model.count } do
            handle event
          end

          model = Orca::Model.find_by!(pipeline_id: event.pipeline_id)
          assert_equal old_org, model.organization,
            "does not change the organization"
        end

        test "does nothing if the resource is empty" do
          event = build(:orca_model_deployment_event, :active, :inference, resource: "")

          assert_no_difference -> { Orca::Model.count } do
            assert_raises Orca::Hydro::ModelDeploymentEventHandler::Error do
              handle event
            end
          end
        end

        test "does nothing if the deployment is empty" do
          event = build(:orca_model_deployment_event, :active, :inference, deployment: "")

          assert_no_difference -> { Orca::Model.count } do
            assert_raises Orca::Hydro::ModelDeploymentEventHandler::Error do
              handle event
            end
          end
        end

        test "does nothing if the organization does not exist" do
          event = build(:orca_model_deployment_event, :active, :inference)
          Organization.delete(event.organization.id)

          assert_no_difference -> { Orca::Model.count } do
            handle event
          end

          assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: %w[
            status:active
            usage:inference
            organization:false
            model_action:none
          ]
        end
      end
    end

    [:inactive, :deleting, :deleted].each do |status|
      context "#{status}" do
        context "gating" do
          test "is ignored" do
            event = build(:orca_model_deployment_event, status, :gating)
            create(:orca_model, pipeline_id: event.pipeline_id)

            assert_no_difference -> { Orca::Model.count } do
              handle event
            end

            assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
              "status:#{status}",
              "usage:gating",
              "organization:true",
              "model_action:none",
            ]
          end
        end

        context "inference" do
          test "deletes existing model" do
            event = build(:orca_model_deployment_event, :inference, status)
            model = create(:orca_model, pipeline_id: event.pipeline_id)

            assert_difference -> { Orca::Model.count }, -1 do
              handle event
            end

            refute Orca::Model.exists?(model.id),
              "deletes the model"

            assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
              "status:#{status}",
              "usage:inference",
              "organization:true",
              "model_action:delete",
            ]
          end

          test "does nothing if the model does not exist" do
            event = build(:orca_model_deployment_event, :inference, status)

            assert_no_difference -> { Orca::Model.count } do
              handle event
            end

            assert_dogstats_increment 1, "github.orca.model_deployment_event", tags: [
              "status:#{status}",
              "usage:inference",
              "organization:true",
              "model_action:none",
            ]
          end
        end
      end
    end
  end
end
