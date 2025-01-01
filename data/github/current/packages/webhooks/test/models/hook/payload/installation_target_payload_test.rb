# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadInstallationTargetPayloadTest < GitHub::TestCase
  context "v3" do
    context "renamed" do
      test "user" do
        user = create(:user)

        options = {
          target_id: user.id,
          target_type: "User",
          changes: { old_login: "old-login" },
        }

        event   = Hook::Event::InstallationTargetEvent.new(options)
        payload = Hook::Payload::InstallationTargetPayload.new(event)

        v3 = payload.to_hash

        assert_equal :renamed, v3[:action]
        assert_equal "User", v3[:target_type]

        assert_equal v3[:account][:id], user.id
        assert_equal v3[:changes][:login][:from], options[:changes][:old_login]
      end

      test "organization" do
        org = create(:organization)

        options = {
          target_id: org.id,
          target_type: "Organization",
          changes: { old_login: "old-login" },
        }

        event   = Hook::Event::InstallationTargetEvent.new(options)
        payload = Hook::Payload::InstallationTargetPayload.new(event)

        v3 = payload.to_hash

        assert_equal :renamed, v3[:action]
        assert_equal "Organization", v3[:target_type]

        assert_equal v3[:account][:id], org.id
        assert_equal v3[:changes][:login][:from], options[:changes][:old_login]
      end

      test "business" do
        business = create(:business)

        options = {
          target_id: business.id,
          target_type: "Business",
          changes: { slug_was: "old-slug" },
        }

        event   = Hook::Event::InstallationTargetEvent.new(options)
        payload = Hook::Payload::InstallationTargetPayload.new(event)

        v3 = payload.to_hash

        assert_equal :renamed, v3[:action]
        assert_equal "Business", v3[:target_type]

        assert_equal v3[:account][:id], business.id
        assert_equal v3[:changes][:slug][:from], options[:changes][:slug_was]
      end
    end
  end
end
