# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::AutoPayTest < GitHub::BillingTestCase
  fixtures do
    @user = create :user, :zuora
    @business = create :business
    @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
  end

  context "#enable!" do
    test "enables flag on Zuora" do
      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override
    end

    test "enables flag on Zuora for Business" do
      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @business,
        reason: :customer_initiated
    end

    test "removes given reason from Set of auto_pay_reasons" do
      @user.customer.update auto_pay_reasons: Set[:staff_override]

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override

      assert_empty @user.reload.customer.auto_pay_reasons
    end

    test "adds audit log entry" do
      events = subscribe("account.toggle_auto_pay")
      actor = create :user

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @user,
        actor: actor,
        reason: :staff_override

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        actor: actor.login,
        actor_id: actor.id,
        auto_pay_status: true,
        auto_pay_reason: :staff_override
      }
      assert_equal expected_payload, events.pop.payload
    end

    test "adds audit log entry for Business" do
      events = subscribe("account.toggle_auto_pay")
      actor = @business.owners.first

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @business,
        actor: actor,
        reason: :customer_initiated

      expected_payload = {
        business: @business.slug,
        business_id: @business.id,
        actor: actor.login,
        actor_id: actor.id,
        auto_pay_status: true,
        auto_pay_reason: :customer_initiated
      }
      assert_equal expected_payload, events.pop.payload
    end

    test "tracks stats for auto_pay_reason" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.customer.update auto_pay_reasons: Set[:staff_override, :trade_controls]

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }]).twice
      Customer.any_instance.expects(:auto_pay?).returns(false).twice

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override

      expected_tags = ["type:remove", "reason:staff_override", "empty_reasons:false"]
      assert_equal 1, GitHub.dogstats.increments("account.auto_pay_reason", tags: expected_tags).count

      Billing::AutoPay.enable! \
        account: @user,
        reason: :trade_controls

      expected_tags = ["type:remove", "reason:trade_controls", "empty_reasons:true"]
      assert_equal 1, GitHub.dogstats.increments("account.auto_pay_reason", tags: expected_tags).count
    end

    test "doesn't update auto_pay_reason if reason isn't in the current list" do
      @user.customer.update auto_pay_reasons: Set[:india_rbi]

      Customer.any_instance.expects(:update).never

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override
    end

    test "doesn't call zuora if autopay is already enabled" do
      @user.customer.update auto_pay_reasons: Set[:staff_override]

      Zuorest::Model::Account.any_instance.expects(:update!).never
      Customer.any_instance.expects(:auto_pay?).returns(true)

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override

      assert_equal @user.reload.customer.auto_pay_reasons, Set[]
    end

    test "doesn't enable AutoPay on Zuora if a eligible reason still exists" do
      @user.customer.update auto_pay_reasons: Set[:india_rbi, :staff_override]

      Zuorest::Model::Account.any_instance.expects(:update!).never

      Billing::AutoPay.enable! \
        account: @user,
        reason: :staff_override
    end

    test "doesn't enable AutoPay on Zuora for Business if a forbidden reason still exists" do
      @business.customer.update auto_pay_reasons: Set[:india_rbi]

      Zuorest::Model::Account.any_instance.expects(:update!).never

      Billing::AutoPay.enable! \
        account: @business,
        reason: :staff_override
    end

    test "enables AutoPay on Zuora for Business if allowed reason still exists" do
      @business.customer.update auto_pay_reasons: Set[:customer_initiated]

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: true)
        .returns([{ "Success" => true }])
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.enable! \
        account: @business,
        reason: :customer_initiated
    end
  end

  context "#disable!" do
    test "disables flag on Zuora " do
      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @user,
        reason: :staff_override
    end

    test "disables flag on Zuora for Business" do
      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @business,
        reason: :customer_initiated
    end

    test "adds given reason to Set of Customer#auto_pay_reasons" do
      @user.customer.update auto_pay_reasons: Set[:staff_override]

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @user,
        actor: nil,
        reason: :india_rbi

      assert_equal @user.reload.customer.auto_pay_reasons, Set[:staff_override, :india_rbi]
    end

    test "adds audit log entry" do
      events = subscribe("account.toggle_auto_pay")
      actor = create :user

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @user,
        actor: actor,
        reason: :staff_override

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        actor: actor.login,
        actor_id: actor.id,
        auto_pay_status: false,
        auto_pay_reason: :staff_override
      }
      assert_equal expected_payload, events.pop.payload
    end

    test "adds audit log entry for Business" do
      events = subscribe("account.toggle_auto_pay")
      actor = @business.owners.first

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @business,
        actor: actor,
        reason: :customer_initiated

      expected_payload = {
        business: @business.slug,
        business_id: @business.id,
        actor: actor.login,
        actor_id: actor.id,
        auto_pay_status: false,
        auto_pay_reason: :customer_initiated
      }
      assert_equal expected_payload, events.pop.payload
    end

    test "tracks stats for auto_pay_reasons" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Zuorest::Model::Account.any_instance.expects(:update!)
        .with(AutoPay: false)
        .returns([{ "Success" => true }])

      Billing::AutoPay.disable! \
        account: @user,
        reason: :trade_controls

      expected_tags = ["type:add", "reason:trade_controls", "empty_reasons:false"]
      assert_equal 1, GitHub.dogstats.increments("account.auto_pay_reason", tags: expected_tags).count
    end

    test "doesn't add given reason if it's already in auto_pay_reasons when autopay is already disabled" do
      @user.customer.update auto_pay_reasons: Set[:staff_override]

      Customer.any_instance.expects(:update).never
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.disable! \
        account: @user,
        actor: nil,
        reason: :staff_override

      assert_equal @user.reload.customer.auto_pay_reasons, Set[:staff_override]
    end

    test "doesn't call zuora if autopay is already disabled" do
      @user.customer.update auto_pay_reasons: Set[:staff_override]

      Zuorest::Model::Account.any_instance.expects(:update!).never
      Customer.any_instance.expects(:auto_pay?).returns(false)

      Billing::AutoPay.disable! \
        account: @user,
        actor: nil,
        reason: :india_rbi

      assert_equal @user.reload.customer.auto_pay_reasons, Set[:staff_override, :india_rbi]
    end

    test "raises an error when the provided reason isn't a valid option" do
      assert_raises ArgumentError do
        Billing::AutoPay.disable! \
          account: @user,
          actor: nil,
          reason: :invalid_reason
      end
    end
  end
end
