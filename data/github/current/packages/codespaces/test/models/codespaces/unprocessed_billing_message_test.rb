# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesUnprocessedBillingMessageTest < GitHub::TestCase
  context "validations" do
    test "ensure presence checks" do
      message = build :codespace_unprocessed_billing_message,
        message_id: nil,
        azure_storage_account_name: nil,
        body: nil

      refute_predicate message, :valid?
      assert_includes message.errors[:message_id], "can't be blank"
      assert_includes message.errors[:azure_storage_account_name], "can't be blank"
      assert_includes message.errors[:body], "can't be blank"
    end

    test "ensures message_id is a 36-char guid" do
      message = build :codespace_unprocessed_billing_message,
        message_id: "ABCDEFG"

      refute_predicate message, :valid?
      assert_includes message.errors[:message_id], "is the wrong length (should be 36 characters)"

      message.message_id = ("X" * 37)
      refute_predicate message, :valid?
      assert_includes message.errors[:message_id], "is the wrong length (should be 36 characters)"

      message.message_id = ("X" * 36)
      assert_predicate message, :valid?
    end

    test "ensures azure_storage_account_name is an appropriate length" do
      message = build :codespace_unprocessed_billing_message,
        azure_storage_account_name: "ST"

      refute_predicate message, :valid?
      assert_includes message.errors[:azure_storage_account_name], "is too short (minimum is 3 characters)"

      message.azure_storage_account_name = ("X" * 25)
      refute_predicate message, :valid?
      assert_includes message.errors[:azure_storage_account_name], "is too long (maximum is 24 characters)"

      message.azure_storage_account_name = "STR"
      assert_predicate message, :valid?

      message.azure_storage_account_name = "WestUs2-Storage-Queue"
      assert_predicate message, :valid?

      message.azure_storage_account_name = ("X" * 24)
      assert_predicate message, :valid?
    end
  end
end
