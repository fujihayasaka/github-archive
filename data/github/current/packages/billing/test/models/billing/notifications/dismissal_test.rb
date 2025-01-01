# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Notifications::DismissalTest < GitHub::TestCase
  setup do
    @key = "threshold_entitlements_info"
    @product_tag = "actions"
    @actor = create :credit_card_user
  end

  context "#create" do
    test "sets a KV record with billing specific data for target account" do
      Timecop.freeze do
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(@key, product_tag: @product_tag)

        base_key = "#{@key}.#{@product_tag}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "sets expiration for 32 days later to minimize stored values" do
      Timecop.freeze do
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(@key, product_tag: @product_tag)
        billing_notice_key = dismiss.send :add_billing_values, @key, @product_tag

        # Allow for one our of drift because of summer/winter time
        assert_in_delta 32.days.from_now.to_i, Billing::Kv.store.ttl(billing_notice_key).value!.to_i, 1.hour
      end
    end

    test "adds billing identifier for businesses" do
      Timecop.freeze do
        business = create :business
        dismiss = Billing::Notifications::Dismissal.new(account: business, actor_id: @actor.id)
        dismiss.create(@key, product_tag: @product_tag)

        base_key = "#{@key}.#{@product_tag}.actor-#{@actor.id}"
        account_key = ".account-business-#{business.id}"
        cycle_key = ".cycle-#{business.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "only dismisses for approved notices" do
      Timecop.freeze do
        invalid_key = "invalid_key"
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(invalid_key, product_tag: @product_tag)

        base_key = "#{invalid_key}.#{@product_tag}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        refute Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "only dismisses for approved products" do
      Timecop.freeze do
        invalid_product = "invalid_product"
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(@key, product_tag: invalid_product)

        base_key = "#{@key}.#{invalid_product}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        refute Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "works for unknows key if starts with billing_platform" do
      Timecop.freeze do
        valid_billing_platform_key = "billing_platform-budget_123-100-threshold_70"
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(valid_billing_platform_key, product_tag: @product_tag)

        base_key = "#{valid_billing_platform_key}.#{@product_tag}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "works for unknows product key if it starts with billing_platform" do
      Timecop.freeze do
        billing_platform_product_tag = "billing_platform_SkuPricing"
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(@key, product_tag: billing_platform_product_tag)

        base_key = "#{@key}.#{billing_platform_product_tag}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        key_with_billing_data = base_key + account_key + cycle_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "uses a matching budget when available" do
      Timecop.freeze do
        spending_limit_key = "threshold_spending_limit_info"
        budget = create :billing_budget, :enforce, owner: @actor, spending_limit_in_subunits: 1_00
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(spending_limit_key, product_tag: @product_tag)

        base_key = "#{spending_limit_key}.#{@product_tag}.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        budget_key = ".budget-#{budget.slug}"
        key_with_billing_data = base_key + account_key + cycle_key + budget_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "uses a shared budget for a spending limit tag" do
      Timecop.freeze do
        spending_limit_key = "threshold_spending_limit_info"
        budget = create :billing_budget, :enforce, owner: @actor, spending_limit_in_subunits: 1_00
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(spending_limit_key, product_tag: "spending_limit")

        base_key = "#{spending_limit_key}.spending_limit.actor-#{@actor.id}"
        account_key = ".account-user-#{@actor.id}"
        cycle_key = ".cycle-#{@actor.current_metered_billing_cycle_starts_at.to_i}"
        budget_key = ".budget-#{budget.slug}"
        key_with_billing_data = base_key + account_key + cycle_key + budget_key

        assert Billing::Kv.store.get(key_with_billing_data).value!
      end
    end

    test "notice refreshes when spending limit amount changes" do
      Timecop.freeze do
        spending_limit_key = "threshold_spending_limit_info"
        budget = create :billing_budget, :enforce, owner: @actor, spending_limit_in_subunits: 1_00
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(spending_limit_key, product_tag: @product_tag)
        budget.update spending_limit_in_subunits: 1_20

        billing_notice_key = dismiss.send :add_billing_values, spending_limit_key, @product_tag
        refute Billing::Kv.store.get(billing_notice_key).value!
      end
    end

    test "doesn't use budget for entitlement notices" do
      Timecop.freeze do
        entitlement_key = "threshold_entitlements_info"
        budget = create :billing_budget, :enforce, owner: @actor, spending_limit_in_subunits: 1_00
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(entitlement_key, product_tag: @product_tag)
        budget.update spending_limit_in_subunits: 1_20

        billing_notice_key = dismiss.send :add_billing_values, entitlement_key, @product_tag
        assert Billing::Kv.store.get(billing_notice_key).value!
      end
    end
  end

  context "#exists" do
    test "returns false if the notice has been dismissed" do
      Timecop.freeze do
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)
        dismiss.create(@key, product_tag: @product_tag)

        assert dismiss.exists?(@key, product_tag: @product_tag)
      end
    end

    test "returns false when the notice hasn't yet been dismissed" do
      Timecop.freeze do
        dismiss = Billing::Notifications::Dismissal.new(account: @actor, actor_id: @actor.id)

        refute dismiss.exists?(@key, product_tag: @product_tag)
      end
    end
  end
end
