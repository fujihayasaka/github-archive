# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::MeteredLicenseTransitionComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @business = create(:business)
  end

  test "renders the metered licenses transition component" do
    render_inline(Licensing::MeteredLicenseTransitionComponent.new(business: @business), allowed_queries: 5)

    assert_selector "metered-license-transition"
  end

  test "Allows transitioning to volume licensing when on metered" do
    @business.customer.metered_ghe = true

    render_inline(Licensing::MeteredLicenseTransitionComponent.new(business: @business), allowed_queries: 1)

    assert_text "Change to volume licensing"
  end

  test "Transition button disabed when all conditions are not met" do
    @business.customer.metered_ghe = false
    @business.customer.stub(:has_active_vss_enterprise_agreement?, true) do
      refute Licensing::MeteredLicenseTransitionComponent.new(business: @business).can_transition_to_metered?
    end
  end

  test "Transition button disabed when there is an active enterprise agreement" do
    create(:enterprise_agreement, seats: 4, business: @business)
    @business.customer.metered_plan = false
    refute Licensing::MeteredLicenseTransitionComponent.new(business: @business).can_transition_to_metered?
  end

  test "Transition button disabed when azure subscription not setup for azure paper customer" do
    create(:enterprise_agreement, seats: 4, business: @business)
    refute Licensing::MeteredLicenseTransitionComponent.new(business: @business).can_transition_to_metered?
  end

  test "Transition button disabed when on a trial" do
    @business.trial_expires_at = Time.now + 1.day
    @business.customer.metered_plan = true
    refute Licensing::MeteredLicenseTransitionComponent.new(business: @business).can_transition_to_metered?
  end

  test "Transition button is enabled when all conditions are met" do
    @business.customer.metered_ghe = false
    assert Licensing::MeteredLicenseTransitionComponent.new(business: @business).can_transition_to_metered?
  end

  test "Allows transitioning to metered licensing when on volume" do
    @business.customer.metered_ghe = false

    render_inline(Licensing::MeteredLicenseTransitionComponent.new(business: @business), allowed_queries: 4)

    assert_text "Change to metered licensing"
  end
end
