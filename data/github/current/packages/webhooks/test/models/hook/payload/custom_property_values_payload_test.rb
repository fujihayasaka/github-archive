# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyValuesPayloadTest < GitHub::TestCase
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

  test "updated payload should include the action, org, repository, new_property_values and old_property_values" do
    event = Hook::Event::CustomPropertyValuesEvent.new(
      actor_id: @owner.id,
      organization_id: @org.id,
      repository_id: @repo.id,
      new_property_values: { "environment" => "value", "security" => nil, "platform" => %w(ios web), "is_legacy" => "true" },
      old_property_values: { "environment" => nil, "security" => "low", "platform" => %w(android web), "is_legacy" => "false"  },

    )
    payload = Hook::Payload::CustomPropertyValuesPayload.new(event).to_hash

    assert_equal payload[:action], "updated"
    assert_equal payload[:new_property_values], [
      { property_name: "environment", value: "value" },
      { property_name: "security", value: nil },
      { property_name: "platform", value: %w(ios web) },
      { property_name: "is_legacy", value: "true" }
    ]
    assert_equal payload[:old_property_values], [
      { property_name: "environment", value: nil },
      { property_name: "security", value: "low" },
      { property_name: "platform", value: %w(android web) },
      { property_name: "is_legacy", value: "false" }
    ]
  end
end
