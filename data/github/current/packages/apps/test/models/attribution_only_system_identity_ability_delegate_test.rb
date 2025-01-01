# typed: true
# frozen_string_literal: true

require "test_helper"

class AttributionOnlySystemIdentityAbilityDelegateTest < GitHub::TestCase
  fixtures do
    @integration = create_privileged_app_with_capabilities(
      capabilities: { attribution_only_system_identity: true }
    )
  end

  test "cannot be created without a Bot actor attached to a capable app" do
    incapable_app = create_privileged_app_with_capabilities(
      capabilities: { irrelevant_super_power: true }
    )

    assert_raises(ArgumentError) do
      AttributionOnlySystemIdentityAbilityDelegate.new(incapable_app.bot)
    end
  end

  test "can be created with a Bot actor attached to a capable app" do
    ability_delegate = AttributionOnlySystemIdentityAbilityDelegate.new(@integration.bot)

    assert_equal @integration.bot, ability_delegate.bot
    assert_predicate ability_delegate, :can_have_granular_permissions?
  end

  test "#permit? always returns true when the feature is enabled" do
    enable_feature_flag(:attribution_only_system_identity, @integration)
    ability_delegate = AttributionOnlySystemIdentityAbilityDelegate.new(@integration.bot)

    assert ability_delegate.permit?(:irrelevant)
  end

  test "#permit? always returns false when the feature is disabled" do
    disable_feature_flag(:attribution_only_system_identity)
    ability_delegate = AttributionOnlySystemIdentityAbilityDelegate.new(@integration.bot)

    refute ability_delegate.permit?(:irrelevant)
  end
end
