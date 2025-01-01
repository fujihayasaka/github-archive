# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::TransitionRebundleGhasForBusinessJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    User.create_ghost
    @user = create :user
    @org = create :organization
    @org.add_member @user

    @business = create :business, organizations: [@org]
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
  end

  test "does not run if business is already bundled", skip_enterprise: true do
    events = subscribe "business.ghas_rebundled"

    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

    Licensing::TransitionRebundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert event = events.pop, "an event was expected"
    assert_equal "business.ghas_rebundled", event.name
    assert_equal "Business is already on bundled GHAS", event.payload[:result]
    assert_equal false, event.payload[:success]
  end

  test "instruments job errors", skip_enterprise: true do
    events = subscribe "business.ghas_rebundled"

    Business.any_instance.expects(:rebundle_ghas).raises(StandardError.new("failed to rebundle"))

    Licensing::TransitionRebundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_rebundle_ghas_for_business").length

    assert_equal 1, events.length
    assert_equal "failed to rebundle", events.first.payload[:result]
    assert_equal false, events.first.payload[:success]
  end

  test "job emits success post rebundling", skip_enterprise: true do
    events = subscribe "business.ghas_rebundled"

    Licensing::TransitionRebundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_rebundle_ghas_for_business").length

    assert event = events.pop, "an event was expected"
    assert_equal "business.ghas_rebundled", event.name
    assert_equal "Success", event.payload[:result]
    assert_equal true, event.payload[:success]
  end

  test "job updates scheduled transition status", skip_enterprise: true do
    scheduled_transition = create(:licensing_ghas_unbundle_transition, customer: @business.customer, target_sku_state: "bundled")

    Licensing::GhasUnbundleTransition.any_instance.expects(:update!).twice

    Licensing::TransitionRebundleGhasForBusinessJob.perform_now(@business, transition_id: scheduled_transition.id, actor: @user)
  end
end
