# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomMessagesTest < GitHub::TestCase
  context "create_or_update_attributes" do
    test "creates a record if it doesn't exist" do
      CustomMessages.delete_all

      CustomMessages.new.create_or_update_attributes(
        support_url: "http://google.com",
      )

      assert_equal 1, CustomMessages.count
    end

    test "defaults to blank for missing attributes" do
      custom_messages = CustomMessages.new

      custom_messages.create_or_update_attributes(support_url: "url")

      custom_message = CustomMessages.first!
      assert_equal "", custom_message.sign_in_message
      assert_equal "", custom_message.sign_out_message
      assert_equal "", custom_message.suspended_message
      assert_equal "", custom_message.auth_provider_name
      assert_equal "url", custom_message.support_url
    end

    test "updates a record if it exists, falling back to default if no value set" do
      @custom_messages = create(:custom_messages,
        suspended_message: " ",
        support_url: "http://www.example.com",
      )

      @custom_messages.create_or_update_attributes(
        suspended_message: "You're suspended.",
        auth_provider_name: "Okta",
      )

      custom_message = CustomMessages.first!
      assert_equal "Hello, sign in", custom_message.sign_in_message
      assert_equal "Goodbye, sign out", custom_message.sign_out_message
      assert_equal "You're suspended.", custom_message.suspended_message
      assert_equal "http://www.example.com", custom_message.support_url
      assert_equal "Okta", custom_message.auth_provider_name
    end

    test "ensures sign_in_message is UTF-8 encoded when created" do
      CustomMessages.new.create_or_update_attributes(
        sign_in_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, CustomMessages.first!.sign_in_message.encoding
    end

    test "ensures sign_in_message is UTF-8 encoded when updated" do
      custom_messages = create(:custom_messages,
        sign_in_message: "sign up",
      )
      custom_messages.create_or_update_attributes(
        sign_in_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, custom_messages.sign_in_message.encoding
    end

    test "ensures sign_out_message is UTF-8 encoded when created" do
      CustomMessages.new.create_or_update_attributes(
        sign_out_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, CustomMessages.first!.sign_out_message.encoding
    end

    test "ensures sign_out_message is UTF-8 encoded when updated" do
      custom_messages = create(:custom_messages,
        sign_out_message: "sign up",
      )
      custom_messages.create_or_update_attributes(
        sign_out_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, custom_messages.sign_out_message.encoding
    end

    test "ensures suspended_message is UTF-8 encoded when created" do
      CustomMessages.new.create_or_update_attributes(
        suspended_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, CustomMessages.first!.suspended_message.encoding
    end

    test "ensures suspended_message is UTF-8 encoded when updated" do
      custom_messages = create(:custom_messages,
        suspended_message: "sign up",
      )
      custom_messages.create_or_update_attributes(
        suspended_message: "日本語".b,
      )
      assert_equal Encoding::UTF_8, custom_messages.suspended_message.encoding
    end
  end
end
