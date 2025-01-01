# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::TransitionUnbundleGhasForBusinessJobTest < GitHub::TestCase
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
    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
  end

  test "does not run if business is already unbundled", skip_enterprise: true do
    events = subscribe "business.ghas_unbundled"

    @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)

    Licensing::TransitionUnbundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert event = events.pop, "an event was expected"
    assert_equal "business.ghas_unbundled", event.name
    assert_equal "Business is already on unbundled SKUs", event.payload[:result]
    assert_equal false, event.payload[:success]
  end

  test "instruments job errors" do
    events = subscribe "business.ghas_unbundled"

    Business.any_instance.expects(:unbundle_ghas).raises(StandardError.new("failed to unbundle"))

    Licensing::TransitionUnbundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_unbundle_ghas_for_business").length

    assert_equal 1, events.length
    assert_equal "failed to unbundle", events.first.payload[:result]
    assert_equal false, events.first.payload[:success]
  end

  test "job emits success post unbundling", skip_enterprise: true do
    events = subscribe "business.ghas_unbundled"

    Licensing::TransitionUnbundleGhasForBusinessJob.perform_now(@business, actor: @user)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_unbundle_ghas_for_business").length

    assert event = events.pop, "an event was expected"
    assert_equal "business.ghas_unbundled", event.name
    assert_equal "Success", event.payload[:result]
    assert_equal true, event.payload[:success]
  end

  test "job updates scheduled transition status", skip_enterprise: true do
    scheduled_transition = create(:licensing_ghas_unbundle_transition, customer: @business.customer)

    Licensing::GhasUnbundleTransition.any_instance.expects(:update!).twice

    Licensing::TransitionUnbundleGhasForBusinessJob.perform_now(@business, transition_id: scheduled_transition.id, actor: @user)
  end
end
