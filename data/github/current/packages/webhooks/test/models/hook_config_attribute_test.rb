# typed: true
# frozen_string_literal: true

require "test_helper"

class HookConfigAttributeTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  context "validates" do
    test "uniqueness of key per hook" do
      hook = create(:hook, :org)

      attribute = HookConfigAttribute.create(
        hook_id: hook.id,
        key: "key",
        value: "value",
      )

      dupe = HookConfigAttribute.create(
        hook_id: hook.id,
        key: "key",
        value: "value",
      )
      refute_predicate dupe, :valid?
      refute_empty dupe.errors[:key]

      dupe2 = HookConfigAttribute.create(
        hook_id: hook.id,
        key: "KEY",
        value: "value",
      )
      refute_predicate dupe2, :valid?
      refute_empty dupe2.errors[:key]
    end

    test "value must not be nil" do
      hook = create(:hook, :org)

      attribute = HookConfigAttribute.create(
        hook_id: hook.id,
        key: "key",
        value: nil,
      )

      refute_predicate attribute, :valid?
      assert_includes attribute.errors[:value], "can't be blank"
    end
  end

  test "supports emoji for value" do
    hook = create(:hook, :org)

    attribute = HookConfigAttribute.create(
      hook_id: hook.id,
      key: "key",
      value: "we ❤️ emojis",
    )

    assert_multibyte_tracked_changes(attribute, :value)
  end
end
