# typed: true
# frozen_string_literal: true

require "test_helper"

class HookConfigAttributeTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  extend EncryptedColumnTestHelper

  test_encrypted_column(:hook_config_attribute, :value)

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

  test "supports database transactions without an HTTP request" do
    hook = create(:hook, :org)
    hook.update!(config_attribute_records: [
      build(:hook_config_attribute, key: "url", value: "http://localhost:5014/webhook"),
      build(:hook_config_attribute, key: "secret", value: "irrelevant")
    ])
  end
end
