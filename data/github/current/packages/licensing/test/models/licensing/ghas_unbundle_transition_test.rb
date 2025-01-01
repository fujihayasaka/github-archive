# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::GhasUnbundleTransitionTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @user = create(:user)
  end

  test "requires a customer" do
    transition = Licensing::GhasUnbundleTransition.new
    refute transition.valid?
    refute_empty transition.errors[:customer]
  end

  test "requires a valid target SKU state" do
    assert_raises ArgumentError do
      Licensing::GhasUnbundleTransition.new(
        target_sku_state: "invalid",
      )
    end
  end

  test "requires a valid status" do
    assert_raises ArgumentError do
      Licensing::GhasUnbundleTransition.new(
        status: "invalid"
      )
    end
  end

  test "requires a transition_date" do
    transition = Licensing::GhasUnbundleTransition.new
    refute transition.valid?
    refute_empty transition.errors[:transition_date]
  end

  test "Transition must be in the future" do
    transition = Licensing::GhasUnbundleTransition.new(
      transition_date: 2.days.ago,
      customer: @business.customer,
      target_sku_state: "unbundled",
      actor: @user,
    )
    refute transition.valid?
    refute_empty transition.errors[:transition_date]
  end

  test "Must be moving to a different target SKU state", skip_enterprise: true do
    assert @business.advanced_security_products_bundled?
    transition = Licensing::GhasUnbundleTransition.new(
      transition_date: 1.day.from_now,
      target_sku_state: "bundled",
      customer: @business.customer,
      status: "scheduled",
      actor: @user,
    )
    refute transition.valid?
    refute_empty transition.errors[:target_sku_state]
  end

  test "Can't schedule two transitions for the same customer" do
    create(:licensing_ghas_unbundle_transition, customer: @business.customer)
    transition = Licensing::GhasUnbundleTransition.new(
      transition_date: 1.day.from_now,
      target_sku_state: "unbundled",
      customer: @business.customer,
      status: "scheduled",
      actor: @user,
    )
    refute transition.valid?
    refute_empty transition.errors[:status]
  end
end
