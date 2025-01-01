# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCustomPropertyTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @owner = create(:user)
    @org = create(:enterprise_linked_organization, admin: @owner)
    @business = @org.business
    @definition = create :custom_property_definition, source: @org, property_name: "env"
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::CustomPropertyEvent, :action, :definition_id, :property_name
  end

  test "actor is present" do
    event = Hook::Event::CustomPropertyEvent.new(
        action: :created,
        actor_id: @owner.id,
        org_id: @org.id,
        property_name: @definition.property_name,
        definition_id: @definition.id,
      )
    assert event.actor
  end

  test "support target" do
    refute Hook::Event::CustomPropertyEvent.supports_target?(Business.new)
    assert Hook::Event::CustomPropertyEvent.supports_target?(Organization.new)
    refute Hook::Event::CustomPropertyEvent.supports_target?(Repository.new)
  end

  [:created, :deleted, :updated].each do |action|
    context "#{action}" do
      test "deliver the hook for org" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        event = Hook::Event::CustomPropertyEvent.new(
          action: action,
          actor_id: @owner.id,
          org_id: @org.id,
          property_name: @definition.property_name,
          definition_id: @definition.id,
        )
        event.deliver_later

        assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event"
        assert_equal 1, GitHub.dogstats.increments("hooks.job_enqueued.count").count
      end

      test "deliver the hook for enterprise" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        event = Hook::Event::CustomPropertyEvent.new(
          action: action,
          actor_id: @owner.id,
          business_id: @business.id,
          property_name: @definition.property_name,
          definition_id: @definition.id,
        )
        event.deliver_later

        assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event"
        assert_equal 1, GitHub.dogstats.increments("hooks.job_enqueued.count").count
      end
    end
  end

  test "visible_for? org" do
    assert Hook::Event::CustomPropertyEvent.visible_for?(nil, @org)
  end

  test "visible_for? integration" do
    assert Hook::Event::CustomPropertyEvent.visible_for?(nil, create(:integration))
  end

  test "visible_for? enterprise" do
    @business.disable_feature(:enterprise_custom_properties)
    refute Hook::Event::CustomPropertyEvent.visible_for?(nil, @business)
    @business.enable_feature(:enterprise_custom_properties)
    assert Hook::Event::CustomPropertyEvent.visible_for?(nil, @business)
  end
end
