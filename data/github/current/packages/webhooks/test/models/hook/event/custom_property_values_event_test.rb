# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCustomPropertyValuesEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @owner = create :user
    @org = create :organization, admin: @owner
    @repo = create :repository, owner: @org

    env_definition = create :custom_property_definition, source: @org, property_name: "env"
    create :custom_property_value, definition: env_definition, target: @repo, value: "production"

    multiselect_definition = create :custom_property_definition, :multi_select, source: @org
    create :custom_property_value, definition: multiselect_definition, target: @repo, value: "ios"
    create :custom_property_value, definition: multiselect_definition, target: @repo, value: "web"

    legacy_definition = create :custom_property_definition, :true_false, source: @org
    create :custom_property_value, definition: legacy_definition, target: @repo, value: "true"
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::CustomPropertyValuesEvent, :organization_id, :repository_id, :new_property_values, :old_property_values
  end

  test "support target" do
    assert Hook::Event::CustomPropertyValuesEvent.supports_target?(Organization.new)
    assert Hook::Event::CustomPropertyValuesEvent.supports_target?(Repository.new)
    refute Hook::Event::CustomPropertyValuesEvent.supports_target?(Business.new)
  end

  test "actor is present" do
    event = Hook::Event::CustomPropertyValuesEvent.new(
        actor_id: @owner.id,
        organization_id: @org.id,
        repository_id: @repo.id,
        new_property_values: { "environment" => "value", "security" => nil },
        old_property_values: { "environment" => nil, "security" => "low" }
      )
    assert event.actor
  end

  test "repository and organization are present" do
    event = Hook::Event::CustomPropertyValuesEvent.new(
      actor_id: @owner.id,
      organization_id: @org.id,
      repository_id: @repo.id,
      new_property_values: { "environment" => "value", "security" => nil },
      old_property_values: { "environment" => nil, "security" => "low" }
    )

    assert_equal event.target_repository, @repo
    assert_equal event.target_organization, @org
  end

  test "visible_for? class method" do
    assert Hook::Event::CustomPropertyValuesEvent.visible_for?(nil, @org)
    assert Hook::Event::CustomPropertyValuesEvent.visible_for?(nil, @repo)

    user_repo = create :repository, owner: @owner
    refute Hook::Event::CustomPropertyValuesEvent.visible_for?(nil, user_repo)
  end

  test "deliver the hook" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    event = Hook::Event::CustomPropertyValuesEvent.new(
      actor_id: @owner.id,
      organization_id: @org.id,
      repository_id: @repo.id,
      new_property_values: { "environment" => "value", "security" => nil, "platform" => %w(ios web), "is_legacy" => "true" },
      old_property_values: { "environment" => nil, "security" => "low", "platform" => %w(android web), "is_legacy" => "false"  },
    )
    event.deliver_later

    assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event"
    assert_equal 1, GitHub.dogstats.increments("hooks.job_enqueued.count").count
  end
end
