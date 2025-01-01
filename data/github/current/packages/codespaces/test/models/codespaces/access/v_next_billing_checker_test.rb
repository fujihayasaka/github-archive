# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Access::VNextBillingCheckerTest < GitHub::TestCase

  fixtures do
    @user = create(:credit_card_user)
    @user.billing_customer.create_billing_platform_enabled_product(codespaces: true)
    @repository = create(:repository)
    disable_feature_flag(:codespaces_billing_free)
  end

  context "perform" do
    test "calls can_proceed_with_usage with correct arguments" do
      Billing::Platform::Api::Client.any_instance.expects(:can_proceed_with_usage).with(has_entry(usage_key: instance_of(BillingPlatform::Api::V1::UsageKey))).twice.returns({ canProceed: true })
      Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
    end

    test "returns allowed if can bill for storage and compute usage" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_storage").returns(true)
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_compute_d2").returns(true)

      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      assert result.allowed?
    end

    test "returns allowed if can bill for storage and compute usage without user id passed" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_storage").returns(true)
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_compute_d2").returns(true)

      result = Codespaces::Access::VNextBillingChecker.new(@user).perform
      assert result.allowed?
    end

    test "returns disallowed if cannot bill for storage usage" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_storage").returns(false)

      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      refute result.allowed?
    end

    test "returns disallowed if cannot bill for compute usage" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_storage").returns(true)
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_compute_d2").returns(false)

      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      refute result.allowed?
    end

    test "returns disallowed if billable owner is nil" do
      result = Codespaces::Access::VNextBillingChecker.new(nil, user_id: @user.id).perform
      refute result.allowed?
    end

    test "returns allowed if free codespace usage enabled" do
      @user.stubs(:free_codespace_use_enabled?).returns(true)
      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      assert result.allowed?
    end

    test "returns allowed if billable owner is invoiced" do
      @user.stubs(:invoiced?).returns(true)
      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      assert result.allowed?
    end

    test "returns allowed if billing service errors" do
      ::BillingPlatform::Client.any_instance.expects(:can_proceed_with_usage).twice.returns(stub(error: "error"))
      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform
      assert result.allowed?
    end
  end

  context "#billing_client" do
    test "passes 5 second timeout to client when fast_timeout is true" do
      # is_a? stub is to please the sorbet gods
      ::Billing::Platform::Api::Client.expects(:new).with(timeout: 5).returns(stub(is_a?: Billing::Platform::Api::Client))
      checker = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id, fast_timeout: true)
      checker.send(:billing_client)
    end
  end

  context "perform for prebuild" do
    test "returns allowed if can bill for storage usage" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_prebuild_storage").returns(true)

      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform(prebuild: true)
      assert result.allowed?
    end

    test "returns disallowed if cannot bill for storage usage" do
      Codespaces::Access::VNextBillingChecker.any_instance.expects(:can_bill_for_usage?).with("codespaces_prebuild_storage").returns(false)

      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform(prebuild: true)
      refute result.allowed?
    end

    test "returns disallowed if billable owner is nil" do
      result = Codespaces::Access::VNextBillingChecker.new(nil, user_id: @user.id).perform(prebuild: true)
      refute result.allowed?
    end

    test "returns allowed if free codespace usage enabled" do
      @user.stubs(:free_codespace_use_enabled?).returns(true)
      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform(prebuild: true)
      assert result.allowed?
    end

    test "returns allowed if billable owner is invoiced" do
      @user.stubs(:invoiced?).returns(true)
      result = Codespaces::Access::VNextBillingChecker.new(@user, user_id: @user.id).perform(prebuild: true)
      assert result.allowed?
    end
  end
end
