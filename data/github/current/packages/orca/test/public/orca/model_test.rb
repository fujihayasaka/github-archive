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

  context ".latest_for_organization" do
    test "returns nil when no models exist" do
      assert_nil Orca::Model.latest_for_organization(@org)
    end

    test "returns the latest model for the organization" do
      create(:orca_model, organization: @org, created_at: 3.days.ago)
      b = create(:orca_model, organization: @org, created_at: 1.day.ago)
      create(:orca_model, organization: @org, created_at: 2.days.ago)

      assert_equal b, Orca::Model.latest_for_organization(@org)
    end
  end

  context "#resource_deployment" do
    test "joins the resource and deployment with a separator" do
      model = build(:orca_model, resource: "foo", deployment: "bar")
      assert_equal "foo.bar", model.resource_deployment
    end
  end
end
