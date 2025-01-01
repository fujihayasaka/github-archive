# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPlanTest < GitHub::TestCase
  include CodespacesPlanFixtures

  fixtures do
    @codespace = create(:codespace)
    @plan = @codespace.plan

    unless GitHub.enterprise?
      emu = create(:emu)
      @business = emu.enterprise_managed_business
    end
  end

  context "validations" do
    test "ensure that we have a valid environment name" do
      plan = build(:codespace_plan, vscs_target: "bad_enviroment_name")
      refute_predicate plan, :valid?

      assert_includes plan.errors[:vscs_target], "is not included in the list"

      plan.vscs_target = "ppe"
      assert_predicate plan, :valid?
    end

    test "rejects name containing emoji" do
      plan = Codespaces::Plan.new(name: "🐹")
      refute_predicate plan, :valid?
      assert plan.errors[:name].any?
    end

    test "ensures it has a valid subscription" do
      Codespaces::Plan.destroy_all
      plan = build(:codespace_plan, subscription: "abcd")
      refute_predicate plan, :valid?

      assert_includes plan.errors[:subscription], "is the wrong length (should be 36 characters)"

      plan.subscription = GitHub.codespaces_canonical_subscription
      assert_predicate plan, :valid?
    end

    test "ensures it is unique per vscs_target, business_id, and location", skip_enterprise: true do
      assert Codespaces::Plan.create(vscs_target: :production, location: "EastUs", business_id: @business.id)
      plan = Codespaces::Plan.create(vscs_target: :production, location: "EastUs", business_id: @business.id)
      refute_predicate plan, :valid?
    end

    test "ensures presence of location", skip_enterprise: true do
      plan = Codespaces::Plan.create(vscs_target: :production, location: "", business_id: @business.id)
      refute_predicate plan, :valid?
    end
  end

  context "#vscs_target" do
    test "returns a symbol value" do
      plan = Codespaces::Plan.new vscs_target: "production"
      assert_equal :production, plan.vscs_target
    end
  end

  context "#destroy" do
    test "deletes dependent codespaces" do
      codespace = create(:codespace, plan: @plan)

      assert_includes @plan.codespaces, codespace
      assert_changes -> { Codespace.count }, from: 2, to: 0 do
        assert @plan.destroy
      end
    end
  end

  context "#location", skip_enterprise: true do
    test "returns location from database in proxima" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        plan = Codespaces::Plan.for!(location: "EastUs", vscs_target: "production")
        assert_equal "EastUs", plan.location
      end
    end
  end

  context "#subscription", skip_enterprise: true do
    test "it is set to the canonical subscription by default" do
      plan = Codespaces::Plan.new(vscs_target: "production", location: "SouthEastAsia", business_id: @business.id + 1)
      plan.save!

      assert GitHub.codespaces_canonical_subscription, plan.subscription
    end
  end

  context "proxima plans", skip_enterprise: true do
    test "#for! returns plan using plan vscs_target, region, and business id" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        plan = Codespaces::Plan.for!(location: "EastUs", vscs_target: "production")
        refute_nil plan
      end
    end

    test "#for_current_tenant! returns plan using plan vscs_target and business id" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        plan = Codespaces::Plan.for_current_tenant!(vscs_target: "production")
        refute_nil plan
      end
    end

    test "#for_current_tenant! raises error when there are not plans for the vscs_target" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)

        assert_raises(Codespaces::Plan::PlanNotFoundForTenant) do
          Codespaces::Plan.for_current_tenant!(vscs_target: "development")
        end
      end
    end

    test "#for_current_tenant! raises error when there are not plans for the business_id" do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id + 1)

        assert_raises(Codespaces::Plan::PlanNotFoundForTenant) do
          Codespaces::Plan.for_current_tenant!(vscs_target: "production")
        end
      end
    end

    test "#for_current_tenant! with FF enabled prefers the known-stable dotcom plan name" do
      on_multi_tenant_enterprise(tenant: @business) do
        existing_tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        new_tenant_plan = create(:codespace_plan, location: "WestUs", vscs_target: "production", business_id: @business.id)

        # Grabs the newest plan when the FF is disabled
        GitHub.flipper[:codespaces_new_plan_for_current_tenant].disable
        plan = Codespaces::Plan.for_current_tenant!(vscs_target: "production")
        assert_equal new_tenant_plan, plan

        # Grabs the newest plan when the FF is enabled but the stable plan does not exist
        GitHub.flipper[:codespaces_new_plan_for_current_tenant].enable
        plan = Codespaces::Plan.for_current_tenant!(vscs_target: "production")
        assert_equal new_tenant_plan, plan

        # Grabs the stable plan when it exists
        existing_tenant_plan.update(name: Codespaces::Plan::STABLE_DOTCOM_PLAN_NAME)
        plan = Codespaces::Plan.for_current_tenant!(vscs_target: "production")
        assert_equal existing_tenant_plan, plan
      end
    end
  end

  context "canonical plans" do
    test "reports and raises an error if the location isn't found in proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        error_reporter = mock
        error_reporter.expects(:push).with(vscs_target: "production", tenant_id: @business.id, location: "The Moon")
        error_reporter.expects(:report).with { |arg| arg.is_a?(Codespaces::Plan::PlanNotFoundForLocation) }
        assert_raises(Codespaces::Plan::PlanNotFoundForLocation) do
          Codespaces::Plan.for!(vscs_target: "production", location: "The Moon", error_reporter: error_reporter)
        end
      end
    end

    test "reports and raises an error if the target isn't found in proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id)
        error_reporter = mock
        error_reporter.expects(:push).with(vscs_target: "development", tenant_id: @business.id, location: "EastUs")
        error_reporter.expects(:report).with { |arg| arg.is_a?(Codespaces::Plan::PlanNotFoundForLocation) }
        assert_raises(Codespaces::Plan::PlanNotFoundForLocation) do
          Codespaces::Plan.for!(vscs_target: "development", location: "EastUs", error_reporter: error_reporter)
        end
      end
    end

    test "reports and raises an error if the business id isn't found in proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        tenant_plan = create(:codespace_plan, location: "EastUs", vscs_target: "production", business_id: @business.id + 1)
        error_reporter = mock
        error_reporter.expects(:push).with(vscs_target: "production", tenant_id: @business.id, location: "EastUs")
        error_reporter.expects(:report).with { |arg| arg.is_a?(Codespaces::Plan::PlanNotFoundForLocation) }
        assert_raises(Codespaces::Plan::PlanNotFoundForLocation) do
          Codespaces::Plan.for!(vscs_target: "production", location: "EastUs", error_reporter: error_reporter)
        end
      end
    end

    context "unknown location" do
      test "reports and raises an error if the location isn't found" do
        error_reporter = mock
        error_reporter.expects(:push).with(vscs_target: :local, location: "The Moon", tenant_id: nil)
        error_reporter.expects(:report).with { |arg| arg.is_a?(Codespaces::Plan::PlanNotFoundForLocation) }
        assert_raises(Codespaces::Plan::PlanNotFoundForLocation) do
          Codespaces::Plan.for!(vscs_target: :local, location: "The Moon", error_reporter: error_reporter)
        end
      end
    end

    context "production plans" do
      test "returns correct plan for EastUs" do
        plan = Codespaces::Plan.for!(vscs_target: :production, location: "EastUs")
        assert_equal "plan-eastus-prod-1", plan.name
      end
      test "returns correct plan for SouthEastAsia" do
        plan = Codespaces::Plan.for!(vscs_target: :production, location: "SouthEastAsia")
        assert_equal "plan-sea-prod-2", plan.name
      end
      test "returns correct plan for WestEurope" do
        plan = Codespaces::Plan.for!(vscs_target: :production, location: "WestEurope")
        assert_equal "plan-westeur-prod-3", plan.name
      end
      test "returns correct plan for WestUs2" do
        name = T.must(Codespaces::Plan.where(vscs_target: :production, location: "WestUs2").last).name
        plan = Codespaces::Plan.for!(vscs_target: :production, location: "WestUs2")
        assert_equal name, plan.name
      end
    end

    context "ppe plans" do
      test "returns correct plan for SouthEastAsia" do
        plan = Codespaces::Plan.for!(vscs_target: :ppe, location: "SouthEastAsia")
        assert_equal "plan-sea-ppe-5", plan.name
      end

      test "returns correct plan for WestUs2" do
        plan = Codespaces::Plan.for!(vscs_target: :ppe, location: "EastUs")
        assert_equal "plan-eastus-ppe-6", plan.name
      end

      test "returns correct plan for CanadaCentral" do
        plan = Codespaces::Plan.for!(vscs_target: :ppe, location: "CanadaCentral")
        assert_equal "plan-canadacentral-ppe-12", plan.name
      end
    end

    context "development plans" do
      test "returns correct plan for WestEurope" do
        plan = Codespaces::Plan.for!(vscs_target: :development, location: "WestEurope")
        assert_equal "plan-westeur-dev-7", plan.name
      end
      test "returns correct plan for WestUs2" do
        plan = Codespaces::Plan.for!(vscs_target: :development, location: "WestUs2")
        assert_equal "plan-westus2-dev-8", plan.name
      end
    end

    context "local plans" do
      test "returns correct plan for WestUs2" do
        plan = Codespaces::Plan.for!(vscs_target: :local, location: "WestUs2")
        assert_equal "plan-westus2-local-10", plan.name
      end

      test "returns correct plan for WestEurope" do
        plan = Codespaces::Plan.for!(vscs_target: :local, location: "WestEurope")
        assert_equal "plan-westeur-local-9", plan.name
      end
    end
  end
end
