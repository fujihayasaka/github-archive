# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHub::PlanTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  test "plans" do
    if GitHub.enterprise?
      assert_equal 40, GitHub::Plan.all.size
    else
      assert_equal 39, GitHub::Plan.all.size
    end

    assert_equal %w[free micro small medium large],
      GitHub::Plan.user_plans.map(&:name)

    assert_equal %w[free bronze silver gold platinum diamond holmium fermium einsteinium mendelevium curium californium ytterbium aluminium],
      GitHub::Plan.org_plans.map(&:name)

    assert_equal %w[bronze silver gold platinum diamond holmium fermium einsteinium mendelevium curium californium ytterbium aluminium],
      GitHub::Plan.non_free_org_plans.map(&:name)

    assert GitHub::Plan.all_org_plans.map(&:name).exclude?("engineyard")

    assert_equal 39, GitHub::Plan.all.count { |plan| !plan.enterprise? }
  end

  test "enterprise plans" do
    if GitHub.enterprise?
      assert_equal 40, GitHub::Plan.all.size
    else
      assert_equal 39, GitHub::Plan.all.size
    end

    if GitHub.enterprise?
      assert_equal %w(contest emu_user enterprise free hackathon500), GitHub::Plan.free_names
    else
      assert_equal %w(contest emu_user free hackathon500), GitHub::Plan.free_names
    end
  end

  context "#as_json" do
    test "doesn't include the account variable" do
      plan = GitHub::Plan.new "name" => "test_plan"
      plan.account = "test"

      refute plan.as_json["account"]
    end
  end

  context "#actions_included_private_minutes" do
    test "returns 0 for plans without actions included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan"
      })

      assert_equal 0, new_plan.actions_included_private_minutes
    end

    test "returns the included units for plans with actions included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan",
        "github_actions" => { "included_private_minutes" => 10000 }
      })

      assert_equal 10000, new_plan.actions_included_private_minutes
    end

    test "returns the included units based on the effective rate plan" do
      pre_munich_actions_plan = GitHub::Plan.business
      pre_munich_actions_plan.receipt_effective_on = MunichPlan::ACTIONS_CHANGE_DATE - 1.day

      post_munich_actions_plan = GitHub::Plan.business
      post_munich_actions_plan.receipt_effective_on = MunichPlan::ACTIONS_CHANGE_DATE + 1.day

      pre_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::ACTIONS_CHANGE_DATE - 1.day).to_time
      post_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::ACTIONS_CHANGE_DATE + 1.day).to_time
      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "team",
        as_of: pre_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "team",
        as_of: post_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      assert_equal 10_000, pre_munich_actions_plan.actions_included_private_minutes
      assert_equal 3_000, post_munich_actions_plan.actions_included_private_minutes
    end

    test "returns the included units for business_plus plans for enterprise trials for the closest effective override" do
      Timecop.travel("2021-03-25") do
        org = create :organization, plan: "business_plus"

        assert Billing::EnterpriseCloudTrial.eligible?(org)
        Billing::EnterpriseCloudTrial.new(org).create
        assert Billing::EnterpriseCloudTrial.active?(org)

        assert_equal 2000, org.plan.actions_included_private_minutes
      end

      Timecop.travel("2021-11-02") do
        org = create :organization, plan: "business_plus"

        assert Billing::EnterpriseCloudTrial.eligible?(org)
        Billing::EnterpriseCloudTrial.new(org).create
        assert Billing::EnterpriseCloudTrial.active?(org)

        assert_equal 3000, org.plan.actions_included_private_minutes
      end
    end

    if GitHub.billing_enabled?
      test "returns the included units for business_plus plans for expired enterprise trial account" do
        business = create :business, trial_expires_at: 1.month.from_now
        assert_equal 3000, business.plan.actions_included_private_minutes

        business.expire_trial
        business = Business.find(business.id)
        assert_equal "free", business.plan.name
        assert_equal 2000, business.plan.actions_included_private_minutes
      end
    end

    test "returns the included units for business_plus plans where user is on enterprise trial starting before trial entitlements change" do
      Timecop.travel("2021-03-23") do
        org = create :organization, plan: "business_plus"

        assert Billing::EnterpriseCloudTrial.eligible?(org)
        # trial starts before trial minutes change
        Billing::EnterpriseCloudTrial.new(org).create
        assert Billing::EnterpriseCloudTrial.active?(org)

        assert_equal 50000, org.plan.actions_included_private_minutes
      end
    end

    test "returns the default included units for trial users not on the business_plus plan" do
      Timecop.travel("2021-03-25") do
        org = create :organization, plan: "free_with_addons"

        Billing::EnterpriseCloudTrial.any_instance.stubs(:active?).returns(true)

        assert_equal 2000, org.plan.actions_included_private_minutes
      end
    end
  end

  context "#display_name" do
    test "defaults to the plan name when no display is defined" do
      GitHub::Plan.all.each do |plan|
        next if plan.free_with_addons? ||
                plan.pro?              ||
                plan.business?         ||
                plan.business_plus?
        assert_equal plan.name, plan.display_name
      end
    end

    test "returns display name when defined" do
      assert_equal "free", GitHub::Plan.free_with_addons.display_name
      assert_equal "pro", GitHub::Plan.pro.display_name
      assert_equal "team", GitHub::Plan.business.display_name
      assert_equal "enterprise", GitHub::Plan.business_plus.display_name
    end

    test "business cloud is called enterprise when new plans are enabled" do
      assert_equal "enterprise", GitHub::Plan.business_plus.display_name
    end

    test "developer is called pro when new plans are enabled" do
      assert_equal "pro", GitHub::Plan.pro.display_name
    end
  end

  context "#entitlement_plan_name" do
    test "returns free_user when no account is set for a free plan" do
      plan = GitHub::Plan.find("free")
      assert_equal "free_user", plan.entitlement_plan_name
    end

    test "returns enterprise_trial for an Organization on an active enterprise trial" do
      org = create :organization, plan: "business"
      Billing::EnterpriseCloudTrial.new(org).create

      plan = GitHub::Plan.find("business_plus", account: org)
      assert_equal "enterprise_trial", plan.entitlement_plan_name
    end

    test "returns enterprise_trial for a Business on an active enterprise trial" do
      business = create :business, trial_expires_at: 5.days.from_now

      plan = GitHub::Plan.find("business_plus", account: business)
      assert_equal "enterprise_trial", plan.entitlement_plan_name
    end

    test "returns enterprise for business_plus orgs" do
      org = create :organization, plan: "business_plus"
      plan = GitHub::Plan.find("business_plus", account: org)
      assert_equal "enterprise", plan.entitlement_plan_name
    end

    test "returns team for business orgs" do
      org = create :organization, plan: "business"
      plan = GitHub::Plan.find("business", account: org)
      assert_equal "team", plan.entitlement_plan_name
    end

    test "returns free_organaization for free orgs" do
      org = create :organization, plan: "free"
      plan = GitHub::Plan.find("free", account: org)
      assert_equal "free_organization", plan.entitlement_plan_name
    end

    test "returns free_organaization for free_with_addons orgs" do
      org = create :organization, plan: "free_with_addons"
      plan = GitHub::Plan.find("free", account: org)
      assert_equal "free_organization", plan.entitlement_plan_name
    end

    test "returns free_user for free users" do
      user = create :user, plan: "free"
      plan = GitHub::Plan.find("free", account: user)
      assert_equal "free_user", plan.entitlement_plan_name
    end

    test "returns free_user for free_with_addons users" do
      user = create :user, plan: "free_with_addons"
      plan = GitHub::Plan.find("free", account: user)
      assert_equal "free_user", plan.entitlement_plan_name
    end

    test "returns free_user for emu_user users before 2023-08-29" do
      user = create :user, plan: "emu_user"
      plan = GitHub::Plan.find("emu_user", account: user)
      plan.receipt_effective_on = Date.parse("2023-08-28")
      assert_equal "free_user", plan.entitlement_plan_name
    end

    test "returns emu_user for emu_user users starting 2023-08-29" do
      user = create :user, plan: "emu_user"
      plan = GitHub::Plan.find("emu_user", account: user)
      plan.receipt_effective_on = Date.parse("2023-08-29")
      assert_equal "emu_user", plan.entitlement_plan_name

      plan.receipt_effective_on = Date.parse("2024-01-01")
      assert_equal "emu_user", plan.entitlement_plan_name
    end

    test "returns enterprise_for_copilot for businesses that are only using copilot" do
      business = create :business
      plan_sub = create :billing_sales_serve_plan_subscription,
      customer: business.customer,
      billing_start_date:  GitHub::Billing.today - 5.days,
      zuora_rate_plan_charges: {
        Billing::SalesServePlanSubscription::GHEC_FOR_COPILOT_CHARGE_ID => { number: "C-123" }
      }

      plan = GitHub::Plan.find("business_plus", account: business)
      assert_equal "enterprise_for_copilot", plan.entitlement_plan_name
    end

    test "returns nil for plans not otherwise configured" do
      user = create :user, plan: "gold"
      plan = GitHub::Plan.find("gold", account: user)
      assert_nil plan.entitlement_plan_name
    end
  end

  test "find a plan" do
    assert_equal "gold", GitHub::Plan.find("gold").name
    assert_nil GitHub::Plan.find("blakeplan")
  end

  test "find a plan uses account#plan_effective_at as a default" do
    effective_datetime = 15.days.ago
    user = create :user, plan: "new_plan"
    user.expects(:plan_effective_at).returns(effective_datetime)
    new_plan = GitHub::Plan.find! "business", account: user

    assert_equal effective_datetime, new_plan.effective_at
  end

  test "find! a plan raises for unknown plan" do
    assert_equal "gold", GitHub::Plan.find!("gold").name
    assert_raises(GitHub::Plan::Error) do
      GitHub::Plan.find!("unknown")
    end
  end

  test "plan methods" do
    assert_equal GitHub::Plan.find("free"), GitHub::Plan.free
    assert_equal GitHub::Plan.find("micro"), GitHub::Plan.micro
    assert_equal GitHub::Plan.find("silver"), GitHub::Plan.silver
    assert_equal GitHub::Plan.find("platinum"), GitHub::Plan.platinum
    assert_equal GitHub::Plan.find("business"), GitHub::Plan.business
    assert_equal GitHub::Plan.find("business_plus"), GitHub::Plan.business_plus
  end

  test "find org plan for coupon discount in $USD" do
    plan = GitHub::Plan.org_plan_for_discount(100.0)
    assert_equal "gold", plan.name
  end

  test "find user plan for coupon discount in $USD" do
    plan = GitHub::Plan.user_plan_for_discount(12.0)
    assert_equal "small", plan.name
  end

  test "free plan" do
    if GitHub.enterprise?
      assert_equal 5, GitHub::Plan.all.count { |plan| plan.free? }
    else
      assert_equal 4, GitHub::Plan.all.count { |plan| plan.free? }
    end
    assert GitHub::Plan.find("free").free?
    assert GitHub::Plan.find("contest").free?
    refute GitHub::Plan.find("giga").free?
    refute GitHub::Plan.find("free_with_addons").free?
  end

  test "free_with_addons?" do
    assert GitHub::Plan.find("free_with_addons").free_with_addons?
    refute GitHub::Plan.find("free").free_with_addons?
    refute GitHub::Plan.find("bronze").free_with_addons?
  end

  test "biggest_user_plan" do
    assert_equal "large", GitHub::Plan.biggest_user_plan.name
  end

  test "upgradeable user plan" do
    refute GitHub::Plan.find("free").upgradeable? # free has unlimited repos, therefore cannot be upgraded to more repos
    assert  GitHub::Plan.find("small").upgradeable?
    refute GitHub::Plan.find("large").upgradeable?
    refute GitHub::Plan.find("giga").upgradeable?
  end

  test "biggest_org_plan" do
    assert_equal "aluminium", GitHub::Plan.biggest_org_plan.name
  end

  test "upgradeable org plan" do
    assert GitHub::Plan.find("bronze").upgradeable?
    if ::GitHub.billing_enabled?
      refute GitHub::Plan.find("aluminium").upgradeable?
    end

    # hidden plans
    refute GitHub::Plan.find("berkelium").upgradeable?
    refute GitHub::Plan.find("unlimited").upgradeable?
  end

  test "paid plan" do
    refute GitHub::Plan.find("free").paid?

    plans = GitHub::Plan.all.select(&:paid?)
    assert_equal 35, plans.size
  end

  test "legacy plan" do
    refute GitHub::Plan.find("free").legacy?

    assert GitHub::Plan.find("mega").legacy?
    assert GitHub::Plan.find("giga").legacy?
    assert GitHub::Plan.find("large").legacy?
  end

  test "per_seat?" do
    business = GitHub::Plan.business
    assert business.per_seat?
    assert business.orgs?
    assert business.hidden?
    assert business.paid?
    refute business.free?
  end

  test "999999 repositories effectively means unlimited private repositories" do
    # Asserting to avoid regression in the desktop apps as they rely on the
    # API to get user plan data and need to replicate the logic that >= 999999
    # repositories effectively means "unlimited private repositories"
    assert_equal 999999, GitHub::Plan.business.repos
    assert GitHub::Plan.business.unlimited?
  end

  test "per_repository?" do
    assert GitHub::Plan.bronze.per_repository?
    assert GitHub::Plan.small.per_repository?
    refute GitHub::Plan.free_with_addons.per_repository?
    refute GitHub::Plan.free.per_repository?
    refute GitHub::Plan.business.per_repository?
  end

  test "business?" do
    assert GitHub::Plan.business.business?
  end

  # This plan is assigned to users or organizations who are on the free plan
  # but have added subscription items or asset packs to their account.
  test "free_with_addons plan" do
    assert free_with_addons = GitHub::Plan.free_with_addons
    assert free_with_addons.orgs?
    assert free_with_addons.hidden?
    assert free_with_addons.paid?
    assert free_with_addons.cost == 0
    refute free_with_addons.free?

    # Should include all features and limits of the free plan
    free_with_addons_json = GitHub::Plan.free_with_addons.as_json
    free_json = GitHub::Plan.free.as_json
    %w(features org_features limits org_limits).each do |item|
      assert_subset_hash(
        free_json.dig("options", item),
        free_with_addons_json.dig("options", item),
        "free_with_addons plan should have all #{item} of the free plan"
      )
    end
  end

  test "nano and pico plans are completely hidden" do
    # NB: These plans are only used for the free private repositories
    # experiment. They do not show up otherwise in the UI.
    refute_includes GitHub::Plan.all_user_plans, "nano"
    refute_includes GitHub::Plan.all_user_plans, "pico"
  end

  test "pro plan" do
    # Still hidden from users
    refute_includes GitHub::Plan.all_user_plans, "pro"
    assert GitHub::Plan.pro.pro?
  end

  test "are comparable" do
    assert free = GitHub::Plan.free
    assert free_with_addons = GitHub::Plan.free_with_addons
    assert micro = GitHub::Plan.micro
    assert small = GitHub::Plan.small
    assert medium = GitHub::Plan.medium

    assert_equal micro, micro
    assert micro < small
    assert small > micro
    assert free < free_with_addons

    assert_equal [free, free_with_addons, micro, small, medium],
                 [medium, micro, small, free, free_with_addons].sort
  end

  context "#effective_plan" do
    test "overrides default pricing when changes are in effect" do
      plan_details = {
        name: "new_plan",
        cost: 20,
        pricing_changes: {
          munich_changes: {
            cost: 5,
            effective_at: 5.days.ago.to_datetime.to_s
          }
        }
      }.deep_stringify_keys
      new_plan = GitHub::Plan.new plan_details

      assert_equal 5, new_plan.cost
    end

    test "uses default pricing if changes haven't gone into effect yet" do
      plan_details = {
        name: "new_plan",
        cost: 20,
        pricing_changes: {
          munich_changes: {
            cost: 5,
            effective_at: 5.days.from_now.to_datetime.to_s
          }
        }
      }.deep_stringify_keys
      new_plan = GitHub::Plan.new plan_details

      assert_equal 20, new_plan.cost
    end

    test "pricing reflects changes to receipt_effective_on" do
      plan_details = {
        name: "new_plan",
        cost: 20,
        pricing_changes: {
          munich_changes: {
            cost: 5,
            effective_at: 5.days.ago.to_datetime.to_s
          }
        }
      }.deep_stringify_keys
      new_plan = GitHub::Plan.new plan_details

      assert_equal 5, new_plan.cost
      new_plan.receipt_effective_on = 10.days.ago
      assert_equal 20, new_plan.cost
    end

    test "effective rate plan pricing is the source of truth" do
      plan_details = {
        name: "new_plan",
        cost: 20,
        pricing_changes: {
          munich_changes: {
            cost: 25,
            effective_at: 5.days.ago.to_datetime.to_s
          }
        },
        rate_plans: {
          new_plan_18: {
            cost: 18,
            effective_at: 10.years.ago.to_datetime.to_s
          }
        }
      }.deep_stringify_keys
      new_plan = GitHub::Plan.new plan_details

      assert_equal 18, new_plan.cost
    end

    test "effective rate plan includes pricing changes not covered by the rate plan" do
      plan_details = {
        name: "new_plan",
        cost: 20,
        github_actions: {
          included_private_minutes: 10_000
        },
        pricing_changes: {
          munich_changes: {
            github_actions: {
              included_private_minutes: 3_000
            },
            effective_at: 5.days.ago.to_datetime.to_s
          }
        },
        rate_plans: {
          new_plan_18: {
            cost: 18,
            effective_at: 10.years.ago.to_datetime.to_s
          }
        }
      }.deep_stringify_keys
      new_plan = GitHub::Plan.new plan_details

      assert_equal 18, new_plan.cost
      assert_equal 3_000, new_plan.actions_included_private_minutes
    end
  end

  context "#package_registry_included_bandwidth" do
    test "returns 0 for plans without shared storage included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan"
      })

      assert_equal 0, new_plan.package_registry_included_bandwidth
    end

    test "returns the included units for plans with shared storage included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan",
        "package_registry" => { "included_bandwidth_in_gigabytes" => 2 }
      })

      assert_equal 2, new_plan.package_registry_included_bandwidth
    end

    test "returns the included units based on effective rate plan" do
      pre_munich_plan = GitHub::Plan.pro
      pre_munich_plan.receipt_effective_on = MunichPlan::RELEASE_DATE - 1.day

      post_munich_plan = GitHub::Plan.pro
      post_munich_plan.receipt_effective_on = MunichPlan::RELEASE_DATE + 1.day

      pre_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::RELEASE_DATE - 1.day).to_time
      post_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::RELEASE_DATE + 1.day).to_time
      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "pro",
        as_of: pre_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "pro",
        as_of: post_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      assert_equal 5, pre_munich_plan.package_registry_included_bandwidth
      assert_equal 10, post_munich_plan.package_registry_included_bandwidth
    end
  end

  context "#shared_storage_included_megabytes" do
    test "returns 0 for plans without shared storage included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan"
      })

      assert_equal 0, new_plan.shared_storage_included_megabytes
    end

    test "returns the included units for plans with shared storage included units" do
      new_plan = GitHub::Plan.new({
        "name" => "new_plan",
        "shared_storage" => { "included_megabytes" => 1024 }
      })

      assert_equal 1024, new_plan.shared_storage_included_megabytes
    end

    test "returns the included units based on the effective rate plan" do
      pre_munich_plan = GitHub::Plan.pro
      pre_munich_plan.receipt_effective_on = MunichPlan::RELEASE_DATE - 1.day

      post_munich_plan = GitHub::Plan.pro
      post_munich_plan.receipt_effective_on = MunichPlan::RELEASE_DATE + 1.day

      pre_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::RELEASE_DATE - 1.day).to_time
      post_munich_as_of = GitHub::Billing.date_in_timezone(MunichPlan::RELEASE_DATE + 1.day).to_time
      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "pro",
        as_of: pre_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      Meuse::Client.any_instance.expects(:get_entitlement_plans).with({
        plan_name: "pro",
        as_of: post_munich_as_of,
        customer_id: nil,
        entitlement_names: []
      }).raises(Faraday::ConnectionFailed, "failed") # to also test fallback below

      assert_equal 1024, pre_munich_plan.shared_storage_included_megabytes
      assert_equal 2048, post_munich_plan.shared_storage_included_megabytes
    end
  end

  context "#copilot_for_biz_eligible?" do
    test "returns true for 'free', 'free_with_addons', 'business' and 'business_plus' plans" do
      %w[free free_with_addons business business_plus].each do |plan_name|
        plan = GitHub::Plan.find(plan_name)
        assert plan.copilot_for_biz_eligible?
      end
    end

    test "returns false for 'pro' plan" do
      plan = GitHub::Plan.find("pro")
      refute plan.copilot_for_biz_eligible?
    end

    test "returns true for free organization" do
      org = create(:organization, plan: "free")
      assert org.plan.copilot_for_biz_eligible?
    end

    test "returns false for free user" do
      user = create(:user, plan: "free")
      refute user.plan.copilot_for_biz_eligible?
    end
  end

  context "#advanced_security_eligible?" do
    test "returns true for 'business_plus' plans" do
      plan = GitHub::Plan.find("business_plus")
      assert plan.advanced_security_eligible?
    end

    test "returns false for 'pro' plan" do
      plan = GitHub::Plan.find("pro")
      refute plan.advanced_security_eligible?
    end

    test "returns false for 'team' plan" do
      plan = GitHub::Plan.find("business")
      refute plan.advanced_security_eligible?
    end

    test "returns false for free organization" do
      org = create(:organization, plan: "free")
      refute org.plan.advanced_security_eligible?
    end

    test "returns false for free user" do
      user = create(:user, plan: "free")
      refute user.plan.advanced_security_eligible?
    end
  end

  test "#cost_in_cents" do
    assert_equal 4_00, GitHub::Plan.pro.cost_in_cents
  end

  test "#yearly_cost_in_cents" do
    assert_equal 48_00, GitHub::Plan.pro.yearly_cost_in_cents
  end

  test "#unit_cost_in_cents" do
    assert_equal 4_00, GitHub::Plan.business.unit_cost_in_cents
  end

  test "#yearly_unit_cost_in_cents" do
    assert_equal 48_00, GitHub::Plan.business.yearly_unit_cost_in_cents
  end

  context "#rate plans" do
    test "returns cost of default plan" do
      Timecop.freeze(GitHub::Billing.timezone.local(2019, 1, 25)) do
        assert_equal 250, GitHub::Plan.business_plus.yearly_unit_cost
      end
    end

    test "returns now as default effective_at" do
      Timecop.freeze(Time.zone.now) do
        assert_equal Time.zone.now, GitHub::Plan.business_plus.effective_at
      end
    end

    test "two instances of the same plan can have different effective_at times" do
      date_a = DateTime.parse("2019-04-24T17:00:00")
      date_b = DateTime.parse("2019-04-23T17:00:00")
      plan_a = GitHub::Plan.find("business_plus", effective_at: date_a)
      _plan_b = GitHub::Plan.find("business_plus", effective_at: date_b)

      assert_equal plan_a.effective_at, date_a
    end
  end

  test "#actions_overage_unit_cost" do
    assert_equal BigDecimal("0.008"), GitHub::Plan.pro.actions_overage_unit_cost
    assert_equal BigDecimal("0.008"), GitHub::Plan.business.actions_overage_unit_cost
    assert_equal BigDecimal("0.008"), GitHub::Plan.business_plus.actions_overage_unit_cost
    assert_equal BigDecimal("0.008"), GitHub::Plan.free_with_addons.actions_overage_unit_cost
    assert_equal BigDecimal("0.008"), GitHub::Plan.free.actions_overage_unit_cost

    # Legacy plans are not supported at all
    assert_equal BigDecimal(0), GitHub::Plan.find("californium").actions_overage_unit_cost
  end

  context "#yearly_discount_percentage" do
    test "does not offer a discount if plan effective date is over a year old" do
      Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 25)) do
        plan = GitHub::Plan.business_plus(effective_at: 366.days.ago)
        plan.receipt_effective_on = Date.today

        assert_equal plan.yearly_discount_percentage, 0
      end
    end

    test "offers discount if plan effective date is less than a year old" do
      Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 25)) do
        plan = GitHub::Plan.business_plus(effective_at: 1.year.ago)
        plan.receipt_effective_on = 3.months.ago

        assert_equal plan.yearly_discount_percentage, 8.3333333
      end
    end

    test "returns 0 if no yearly discount is eligible" do
      plan = GitHub::Plan.pro
      assert_equal plan.yearly_discount_percentage, 0
    end
  end

  context "#supports?" do
    test "pulls supported features from plans.yml" do
      assert GitHub::Plan.free.supports?(:repos, visibility: :private)
      assert GitHub::Plan.micro.supports?(:repos, visibility: :private)
      assert GitHub::Plan.pro.supports?(:repos, visibility: :private)
      assert GitHub::Plan.large.supports?(:repos, visibility: :private)
      assert GitHub::Plan.business.supports?(:repos, visibility: :private)

      assert GitHub::Plan.free.supports?(:repos, visibility: :public)
      assert GitHub::Plan.business.supports?(:repos, visibility: :public)

      # Org-specific overrides
      assert GitHub::Plan.free.supports?(:repos, visibility: :public, org: true)
      assert GitHub::Plan.free.supports?(:repos, visibility: :private, org: true)
    end

    test "pulls feature-flag overridden supported features from plans.yml" do
      with_mock_plan_config do
        # make sure the default values are as expected
        assert GitHub::Plan.free.supports?(:pages)
        refute GitHub::Plan.free.supports?(:pages, org: true)
        refute GitHub::Plan.free.supports?(:repos, visibility: :private, org: true)

        # now check for the feature-flagged overrides
        refute GitHub::Plan.free.supports?(:pages, feature_flag: :org_only_pages)
        assert GitHub::Plan.free.supports?(:pages, org: true, feature_flag: :org_only_pages)

        # now use a flag that doesn't contain feature-flagged org overrides to ensure correct values are still pulled
        refute GitHub::Plan.free.supports?(:repos, visibility: :private, org: true, feature_flag: :fifty_private_repos_for_users)
      end
    end

    test "falls back to default supported features when an unknown feature flag is provided" do
      assert GitHub::Plan.free.supports?(:repos, visibility: :private, feature_flag: :a_non_existent_feature)
      assert GitHub::Plan.business.supports?(:repos, visibility: :private, feature_flag: :a_non_existent_feature)

      assert GitHub::Plan.free.supports?(:repos, visibility: :public, feature_flag: :a_non_existent_feature)
      assert GitHub::Plan.business.supports?(:repos, visibility: :public, feature_flag: :a_non_existent_feature)

      # Org-specific overrides
      assert GitHub::Plan.free.supports?(:repos, visibility: :public, org: true, feature_flag: :a_non_existent_feature)
      assert GitHub::Plan.free.supports?(:repos, visibility: :private, org: true, feature_flag: :a_non_existent_feature)
    end

    test "raises an error on unknown features" do
      error = assert_raises GitHub::Plan::UnknownFeatureError do
        GitHub::Plan.free.supports?(:unknown)
      end

      assert_includes error.message, "Unknown feature name passed: :unknown."
    end

    test "doesn't raise an error on unknown features in production" do
      GitHub::AppEnvironment.stubs(:production?).returns(true)
      Failbot.expects(:report).with(instance_of(GitHub::Plan::UnknownFeatureError))

      result = assert_nothing_raised do
        GitHub::Plan.free.supports?(:unknown)
      end

      assert_equal false, result
    end

    test "visibility 'internal' falls back to the 'private' setting" do
      assert GitHub::Plan.free.supports?(:draft_prs, visibility: :public)
      refute GitHub::Plan.free.supports?(:draft_prs, visibility: :private)
      refute GitHub::Plan.free.supports?(:draft_prs, visibility: :internal)

      assert GitHub::Plan.business.supports?(:draft_prs, visibility: :public)
      assert GitHub::Plan.business.supports?(:draft_prs, visibility: :private)
      assert GitHub::Plan.business.supports?(:draft_prs, visibility: :internal)
    end

    test "draft PRs are supported on public repos but only team/business private repos" do
      assert GitHub::Plan.free.supports?(:draft_prs, visibility: :public)
      refute GitHub::Plan.free.supports?(:draft_prs, visibility: :private)

      assert GitHub::Plan.pro.supports?(:draft_prs, visibility: :public)
      refute GitHub::Plan.pro.supports?(:draft_prs, visibility: :private)

      assert GitHub::Plan.large.supports?(:draft_prs, visibility: :public)
      refute GitHub::Plan.large.supports?(:draft_prs, visibility: :private)

      assert GitHub::Plan.business.supports?(:draft_prs, visibility: :public)
      assert GitHub::Plan.business.supports?(:draft_prs, visibility: :private)

      assert GitHub::Plan.business_plus.supports?(:draft_prs, visibility: :public)
      assert GitHub::Plan.business_plus.supports?(:draft_prs, visibility: :private)
    end

    test "memex projectsv2 basic chart features are supported for public projects or paid pro, team, and enterprise cloud plans" do
      assert GitHub::Plan.free.supports?(:projectsv2_charts_basic, visibility: :public)
      refute GitHub::Plan.free.supports?(:projectsv2_charts_basic, visibility: :private)

      assert GitHub::Plan.pro.supports?(:projectsv2_charts_basic, visibility: :public)
      assert GitHub::Plan.pro.supports?(:projectsv2_charts_basic, visibility: :private)

      # Team plan
      assert GitHub::Plan.business.supports?(:projectsv2_charts_basic, visibility: :public)
      assert GitHub::Plan.business.supports?(:projectsv2_charts_basic, visibility: :private)

      # Enterprise Cloud plan
      assert GitHub::Plan.business_plus.supports?(:projectsv2_charts_basic, visibility: :public)
      assert GitHub::Plan.business_plus.supports?(:projectsv2_charts_basic, visibility: :private)

      # Legacy plans have only the features of free plans
      assert GitHub::Plan.large.supports?(:projectsv2_charts_basic, visibility: :public)
      refute GitHub::Plan.large.supports?(:projectsv2_charts_basic, visibility: :private)
    end

    test "memex projectsv2 insights features are not supported on free or pro, limited for team, and basic for enterprise cloud" do
      refute GitHub::Plan.free.supports?(:projectsv2_insights_limited)
      refute GitHub::Plan.free.supports?(:projectsv2_insights_basic)

      refute GitHub::Plan.pro.supports?(:projectsv2_insights_limited)
      refute GitHub::Plan.pro.supports?(:projectsv2_insights_basic)

      # Team plan
      assert GitHub::Plan.business.supports?(:projectsv2_insights_limited)
      refute GitHub::Plan.business.supports?(:projectsv2_insights_basic)

      # Enterprise Cloud plan
      refute GitHub::Plan.business_plus.supports?(:projectsv2_insights_limited)
      assert GitHub::Plan.business_plus.supports?(:projectsv2_insights_basic)

      # Legacy plans have only the features of free plans
      refute GitHub::Plan.large.supports?(:projectsv2_insights_limited)
      refute GitHub::Plan.large.supports?(:projectsv2_insights_basic)
    end

    test "memex projectsv2 insights features are available for enterprise plans", enterprise_only: true do
      assert GitHub::Plan.enterprise.supports?(:projectsv2_insights_basic)
    end

    test "team review requests are not supported on free org private repos" do
      assert GitHub::Plan.free.supports?(:team_review_requests, visibility: :public)
      refute GitHub::Plan.free.supports?(:team_review_requests, visibility: :private)
    end
  end

  context "#supported_org_plans_for_feature" do
    test "supported_org_plans_for_feature" do
      supported = GitHub::Plan.supported_org_plans_for_feature(feature: :repos)
      assert_equal supported.count, GitHub::Plan.all_org_plans.count
    end

    test "raises an error on unknown features" do
      error = assert_raises GitHub::Plan::UnknownFeatureError do
        GitHub::Plan.supported_org_plans_for_feature(feature: :unknown)
      end

      assert_includes error.message, "Unknown feature name passed: :unknown."
    end

    context ":display_commenter_full_name" do
      if GitHub.enterprise?
        test "returns expected supported plans for :private visibility in enterprise on prem" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name, visibilities: [:private])
          assert_equal supported.count, 3
          assert_same_elements supported, [GitHub::Plan.business, GitHub::Plan.business_plus, GitHub::Plan.enterprise]
        end

        test "returns expected supported plans for :public visibility in enterprise on prem" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name, visibilities: [:public])
          assert_equal supported.count, 1
          assert_same_elements supported, [GitHub::Plan.enterprise]
        end

        test "returns expected supported plans for :internal visibility in enterprise on prem" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name, visibilities: [:internal])
          assert_equal supported.count, 3
          assert_same_elements supported, [GitHub::Plan.business, GitHub::Plan.business_plus, GitHub::Plan.enterprise]
        end
      else
        test "returns expected supported plans for all visibilities" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name)
          assert_equal supported.count, 2
          assert_same_elements supported, [GitHub::Plan.business, GitHub::Plan.business_plus]
        end

        test "returns expected supported plans for :private visibility" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name, visibilities: [:private])
          assert_equal supported.count, 2
          assert_same_elements supported, [GitHub::Plan.business, GitHub::Plan.business_plus]
        end

        test "returns expected supported plans for :public visibility" do
          supported = GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name, visibilities: [:public])
          assert_equal supported.count, 0
        end
      end
    end
  end

  context "#limit" do
    test "pulls limits from plans.yml" do
      assert_equal 10_000, GitHub::Plan.free.limit(:collaborators, visibility: :public)
      assert_equal 10_000,      GitHub::Plan.free.limit(:collaborators, visibility: :private)

      # Org-specific overrides
      assert_equal 10_000, GitHub::Plan.free.limit(:repos, visibility: :public)
      assert_equal 10_000, GitHub::Plan.free.limit(:repos, visibility: :private)
      assert_equal 10_000, GitHub::Plan.free.limit(:repos, visibility: :public)
      assert_equal 10_000, GitHub::Plan.free.limit(:repos, visibility: :private)
    end

    test "pulls feature-flag overridden limits from plans.yml" do
      with_mock_plan_config do
        # make sure the default values are as expected
        assert_equal 10_000, GitHub::Plan.free.limit(:repos, visibility: :private), "limit should be unchanged without the feature flag"
        assert_equal 0, GitHub::Plan.free.limit(:repos, visibility: :private, org: true), "org limit should be overridden without feature flag"

        # now check for overrides per the feature flag
        assert_equal 50, GitHub::Plan.free.limit(:repos, visibility: :private, feature_flag: :fifty_private_repos_for_users), "limit should be overridden with the feature flag"
        assert_equal 0, GitHub::Plan.free.limit(:repos, visibility: :private, org: true, feature_flag: :fifty_private_repos_for_users), "org limit override should be unchanged without feature flag"

        # now provide a different feature flag to check for feature-flagged org limit overrides
        assert_equal 50, GitHub::Plan.free.limit(:repos, visibility: :private, org: true, feature_flag: :fifty_private_repos_for_orgs), "org limit override can be overridden with a feature flag"
      end
    end

    test "falls back to default limits if an unknown feature flag is provided" do
      free_invididual_public_limit = GitHub::Plan.free.limit(:repos, visibility: :public)
      free_invididual_private_limit = GitHub::Plan.free.limit(:repos, visibility: :private)
      free_org_public_limit = GitHub::Plan.free.limit(:repos, visibility: :public, org: true)
      free_org_private_limit = GitHub::Plan.free.limit(:repos, visibility: :private, org: true)

      assert_equal free_invididual_public_limit, GitHub::Plan.free.limit(:repos, visibility: :public, feature_flag: :a_non_existent_feature)
      assert_equal free_invididual_private_limit, GitHub::Plan.free.limit(:repos, visibility: :private, feature_flag: :a_non_existent_feature)
      assert_equal free_org_public_limit, GitHub::Plan.free.limit(:repos, visibility: :public, org: true, feature_flag: :a_non_existent_feature)
      assert_equal free_org_private_limit, GitHub::Plan.free.limit(:repos, visibility: :private, org: true, feature_flag: :a_non_existent_feature)
    end

    test "raises an error on unknown features" do
      error = assert_raises GitHub::Plan::UnknownFeatureError do
        GitHub::Plan.free.limit(:unknown)
      end

      assert_includes error.message, "Unknown feature name passed: :unknown."
    end

    test "doesn't raise an error on unknown features in production" do
      GitHub.stubs(:raise_on_unknown_plan_feature?).returns(false)

      Failbot.expects(:report).with(instance_of(GitHub::Plan::UnknownFeatureError))

      result = assert_nothing_raised do
        GitHub::Plan.free.limit(:unknown)
      end

      assert_equal 0, result
    end
  end

  context "#entitlements" do
    test "formats entitlement names" do
      plan = GitHub::Plan.pro
      mock_get_entitlement_plans

      entitlements = plan.entitlements

      assert entitlements.keys.include?(:codespaces_compute)
      assert entitlements.keys.include?(:codespaces_storage)
      assert entitlements.keys.include?(:shared_storage)
      assert entitlements.keys.include?(:packages)
      assert entitlements.keys.include?(:actions)
    end

    test "memoizes get_entitlement_plans call" do
      plan = GitHub::Plan.pro
      mock_get_entitlement_plans(times: 1)

      entitlements = plan.entitlements
      also_entitlements = plan.entitlements
    end

    test "memoization respects method parameters" do
      plan = GitHub::Plan.pro
      mock_get_entitlement_plans(times: 2)

      entitlements = plan.entitlements
      also_entitlements = plan.entitlements

      yesterday = GitHub::Billing.today - 1.day
      plan.receipt_effective_on = yesterday
      yesterdays_entitlements = plan.entitlements
    end

    test "caches entitlements" do
      plan = GitHub::Plan.pro
      plan2 = GitHub::Plan.pro
      mock_get_entitlement_plans(times: 1)

      cache_key = "billing:entitlements:v2:#{plan.entitlement_plan_name}"
      with_cache_enabled do
        assert_nil GitHub.cache.get(cache_key)

        entitlements = plan.entitlements
        refute_nil GitHub.cache.get(cache_key)
        also_entitlements = plan2.entitlements
      end
    end

    test "caches entitlements properly" do
      plan = GitHub::Plan.pro
      plan2 = GitHub::Plan.free # different plan should not use cached entitlements
      mock_get_entitlement_plans(times: 2)

      cache_key = "billing:entitlements:v2:#{plan.entitlement_plan_name}"
      with_cache_enabled do
        assert_nil GitHub.cache.get(cache_key)

        entitlements = plan.entitlements
        refute_nil GitHub.cache.get(cache_key)
        also_entitlements = plan2.entitlements
      end
    end
  end

  def with_mock_plan_config(&block)
    mock_config = [
      GitHub::Plan.new({
        "name" => "free",
        "cost" => 0,
        "orgs" => true,
        "features" => {
          "repos.private" => true,
          "pages" => true,
        },
        "limits" => {
          "repos.private" => 10_000,
          "repos.public" => 10_000,
          "collaborators" => 10_000,
        },
        "org_features" => {
          "repos.private" => false,
          "pages" => false,
        },
        "org_limits" => {
          "repos.private" => 0,
        },
        "feature_flag_overrides" => {
          "org_only_pages" => {
            "features" => {
              "pages" => false,
            },
            "org_features" => {
              "pages" => true,
            },
          },
          "fifty_private_repos_for_users" => {
            "limits" => {
              "repos.private" => 50,
            },
          },
          "fifty_private_repos_for_orgs" => {
            "org_limits" => {
              "repos.private" => 50,
            },
          },
        },
      }),
    ]

    GitHub::Plan.stub(:all, mock_config) { yield }
  end
end
