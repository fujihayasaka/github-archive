# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject::WebsocketDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:verified_user)
    @org_owned_project = create(:memex_project, public: false, owner: @org)
    @user_owned_project = create(:memex_project, public: false, owner: @user)
    @public_project = create(:memex_project, public: true)
  end

  context "#live_updates_channel" do
    test "returns the signed memex channel" do
      GitHub::WebSocket
        .expects(:signed_channel)
        .with(GitHub::WebSocket::Channels.memex(@org_owned_project))
        .returns("signed-channel")

      assert_equal "signed-channel", @org_owned_project.live_updates_channel
    end
  end

  context "#presence_channel" do
    test "returns nil for a public project" do
      assert_nil @public_project.presence_channel
    end

    test "returns nil for a user-owned project" do
      assert_nil @user_owned_project.presence_channel
    end

    test "returns a signed channel at a pinned version for an organization-owned project" do
      GitHub::WebSocket
        .expects(:signed_presence_channel)
        .with do |channel, authz_attributes|

          assert_equal GitHub::WebSocket::Channels.memex(@org_owned_project), channel
          assert authz_attributes.any? { |attribute| attribute.id == "version" && attribute.value.to_i == 5 }
        end
        .returns("signed-channel")

      assert_equal "signed-channel", @org_owned_project.presence_channel
    end
  end

  context "#notify_memex_channel" do
    test "notifies the right channel with the given data" do
      data = { bulkUpdateSuccess: true }
      GitHub::WebSocket.expects(:notify_memex_channel).once.with(@org_owned_project, "memex:#{@org_owned_project.id}", data)

      @org_owned_project.notify_memex_channel(data)
    end
  end
end
