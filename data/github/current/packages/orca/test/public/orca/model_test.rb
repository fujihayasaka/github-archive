# typed: true
# frozen_string_literal: true

require "test_helper"

class OrcaModelTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context "validations" do
    context "organization" do
      test "is valid when organization present" do
        obj = build(:orca_model, organization: @org)
        assert obj.valid?
      end

      test "is valid when another model has same organization" do
        create(:orca_model, organization: @org)
        obj = build(:orca_model, organization: @org)
        assert obj.valid?
      end

      test "is invalid when organization not present" do
        obj = build(:orca_model, organization: nil)
        assert_not obj.valid?
      end
    end

    context "pipeline_id" do
      test "is valid when < 256 chars and unique" do
        obj = build(:orca_model, pipeline_id: "")
        assert obj.valid?
      end

      test "is invalid when not unique" do
        pipeline_id = "a" * 255
        create(:orca_model, pipeline_id: pipeline_id)
        obj = build(:orca_model, pipeline_id: pipeline_id)
        assert_not obj.valid?
      end

      test "is invalid when >= 256 chars" do
        obj = build(:orca_model, pipeline_id: "a" * 256)
        assert_not obj.valid?
      end

      test "is invalid when nil" do
        obj = build(:orca_model, pipeline_id: nil)
        assert_not obj.valid?
      end
    end

    context "resource" do
      test "is valid when < 256 chars" do
        obj = build(:orca_model, resource: "")
        assert obj.valid?
      end

      test "is invalid when >= 256 chars" do
        obj = build(:orca_model, resource: "a" * 256)
        assert_not obj.valid?
      end

      test "is invalid when nil" do
        obj = build(:orca_model, resource: nil)
        assert_not obj.valid?
      end
    end

    context "deployment" do
      test "is valid when < 256 chars" do
        obj = build(:orca_model, deployment: "")
        assert obj.valid?
      end

      test "is invalid when >= 256 chars" do
        obj = build(:orca_model, deployment: "a" * 256)
        assert_not obj.valid?
      end

      test "is invalid when nil" do
        obj = build(:orca_model, deployment: nil)
        assert_not obj.valid?
      end
    end
  end

  test "has a valid factory" do
    assert create(:orca_model).valid?
  end

  context ".for_organizations" do
    test "returns nothing when no orgs" do
      assert_empty Orca::Model.for_organizations([])
    end

    test "returns nothing when no models" do
      assert_empty Orca::Model.for_organizations([@org])
    end

    test "returns the models for an org" do
      model = create(:orca_model, organization: @org)

      assert_equal [model],
        Orca::Model.for_organizations([@org])
    end

    test "returns the most recent model for an org" do
      create(:orca_model, organization: @org, created_at: 1.day.ago)
      newest = create(:orca_model, organization: @org, created_at: 1.hour.ago)
      create(:orca_model, organization: @org, created_at: 1.week.ago)

      assert_equal [newest],
        Orca::Model.for_organizations([@org])
    end

    test "returns the first model for each org when multiple orgs" do
      org1 = create(:organization)
      org2 = create(:organization)
      org3 = create(:organization)

      model3 = create(:orca_model, organization: org3, created_at: 1.day.ago)

      create(:orca_model, organization: org1, created_at: 1.day.ago)
      model1 = create(:orca_model, organization: org1, created_at: 1.hour.ago)

      model2 = create(:orca_model, organization: org2, created_at: 1.day.ago)
      create(:orca_model, organization: org2, created_at: 1.week.ago)

      assert_equal [model1, model2, model3],
        Orca::Model.for_organizations([org1, org2, org3]),
        "sorts by org id for stability"
    end

    test "behaves correctly when called with multiple of the same org" do
      model = create(:orca_model, organization: @org)
      assert_equal [model],
        Orca::Model.for_organizations([@org, @org])
    end
  end

  context "#resource_deployment" do
    test "joins the resource and deployment with a separator" do
      model = build(:orca_model, resource: "foo", deployment: "bar")
      assert_equal "foo.bar", model.resource_deployment
    end
  end

  context "#target_for_conditional_access" do
    test "returns the organization if feature flag is on" do
      model = build(:orca_model, organization: @org)
      enable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, @org)
      assert_equal @org, model.target_for_conditional_access
    end

    test "returns :no_target_for_conditional_access if feature flag is off" do
      disable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, @org)
      model = build(:orca_model, organization: @org)
      assert_equal :no_target_for_conditional_access, model.target_for_conditional_access
    end
  end

  context "#multiple_target_for_conditional_access" do
    test "returns a hash of model -> organization as conditional access targets if feature flag is enabled" do
      org1 = create(:organization)
      org2 = create(:organization)
      org3 = create(:organization)

      model1 = create(:orca_model, organization: org1)
      model2 = create(:orca_model, organization: org2)
      model3 = create(:orca_model, organization: org3)

      enable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org1)
      enable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org2)
      enable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org3)

      assert_equal Hash[model1, org1, model2, org2, model3, org3],
        Orca::Model.multiple_target_for_conditional_access([model1, model2, model3])
    end

    test "returns a hash of model -> organization as conditional access targets" do
      org1 = create(:organization)
      org2 = create(:organization)
      org3 = create(:organization)

      model1 = create(:orca_model, organization: org1)
      model2 = create(:orca_model, organization: org2)
      model3 = create(:orca_model, organization: org3)

      disable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org1)
      disable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org2)
      enable_feature_flag(:copilot_custom_models_ip_cap_filter_organization, org3)

      targets = Orca::Model.multiple_target_for_conditional_access([model1, model2, model3])

      assert_equal targets[model1], :no_target_for_conditional_access
      assert_equal targets[model2], :no_target_for_conditional_access
      assert_equal targets[model3], org3
    end

    test "throws if input list doesn't contain orca models" do
      org1 = create(:organization)
      org2 = create(:organization)
      org3 = create(:organization)

      assert_raises ArgumentError do
        Orca::Model.multiple_target_for_conditional_access([org1, org2, org3])
      end
    end
  end
end
