# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Public::Budgets::PermissionTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org1 = create(:organization, admins: [@admin])
    @org2 = create(:organization, admins: [@admin])
    @business = create :business, owners: [@admin], organizations: [@org1, @org2]
  end

  setup do
    GitHub.flipper[:ghe_spending_limits].disable
  end

  context "#show_org_level_budgets_tab?" do
    test "true when FF is on" do
      GitHub.flipper[:ghe_spending_limits].enable

      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      assert permission.show_org_level_budgets_tab?
    end

    test "false when FF is off" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      refute permission.show_org_level_budgets_tab?
    end

    test "false when FF is on but metered billing is disabled" do
      GitHub.flipper[:ghe_spending_limits].enable
      @business.stubs(:plan_metered_billing_eligible?).returns(false)

      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      refute permission.show_org_level_budgets_tab?
    end

    test "true when FF is on and metered billing is disabled on a self serve account" do
      GitHub.flipper[:ghe_spending_limits].enable
      @business.stubs(:plan_metered_billing_eligible?).returns(false)
      @business.stubs(:can_self_serve?).returns(true)
      @business.stubs(:invoiced?).returns(false)

      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      assert permission.show_org_level_budgets_tab?
    end
  end

  context "#show_enterprise_spending_limit_tab?" do
    test "true when FF is off" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      assert permission.show_enterprise_spending_limit_tab?
    end

    test "false when FF is on" do
      GitHub.flipper[:ghe_spending_limits].enable
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      refute permission.show_enterprise_spending_limit_tab?
    end

    test "false when FF is off and metered billing is disabled" do
      @business.stubs(:plan_metered_billing_eligible?).returns(false)
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      refute permission.show_enterprise_spending_limit_tab?
    end

    test "true when FF is off and metered billing is disabled on a self serve account" do
      @business.stubs(:plan_metered_billing_eligible?).returns(false)
      @business.stubs(:can_self_serve?).returns(true)
      @business.stubs(:invoiced?).returns(false)

      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      assert permission.show_enterprise_spending_limit_tab?
    end
  end

  context "#show_spending_limit_tab?" do
    test "returns true if show_metered_billing_configuration? is true" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      permission.expects(:show_metered_billing_configuration?).returns(true)
      assert permission.show_spending_limit_tab?
    end

    test "returns true if show_metered_billing_configuration? is false but show_billing_privileges? is true" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      permission.expects(:show_metered_billing_configuration?).returns(false)
      permission.expects(:show_billing_privileges?).returns(true)
      assert permission.show_spending_limit_tab?
    end

    test "returns false if show_metered_billing_configuration? is false and show_billing_privileges is false" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      permission.expects(:show_metered_billing_configuration?).returns(false)
      permission.expects(:show_billing_privileges?).returns(false)
      refute permission.show_spending_limit_tab?
    end
  end

  context "#show_billing_privileges?" do
    test "returns true if current user is owner, business can self serve, and business is not invoiced" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      @business.expects(:can_self_serve?).returns(true)
      @business.expects(:invoiced?).returns(false)
      assert permission.show_billing_privileges?
    end

    test "returns false if current user is not owner" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      @business.expects(:owner?).returns(false)
      refute permission.show_billing_privileges?
    end

    test "returns false if business can not self serve" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      @business.expects(:can_self_serve?).returns(false)
      refute permission.show_billing_privileges?
    end

    test "returns false if business is invoiced" do
      permission = Billing::Public::Budgets::Permission.new(@business, @admin)
      @business.expects(:can_self_serve?).returns(true)
      @business.expects(:invoiced?).returns(true)
      refute permission.show_billing_privileges?
    end
  end
end
