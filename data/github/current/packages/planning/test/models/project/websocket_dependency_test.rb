# typed: true
# frozen_string_literal: true

require "test_helper"

class Project::WebsocketDependencyTest < GitHub::TestCase
  fixtures do
    @project = create(:project)
  end

  context "#channel" do
    test "returns a channel identifier" do
      assert_equal "projects:#{@project.id}", @project.channel
    end
  end

  context "#metadata_channel" do
    test "returns an identifier for the metadata channel" do
      assert_equal "projects:metadata:#{@project.id}", @project.metadata_channel
    end
  end

  context "#notify_subscribers" do
    test "notifies the right channel" do
      GitHub.context.push(client_uid: "some value")

      expected_payload = {
        foo: "bar",
        state: { columns: @project.columns },
        client_uid: "some value",
        is_project_activity: true,
      }
      GitHub::WebSocket.expects(:notify_project_channel).once
        .with(@project, "projects:#{@project.id}", expected_payload)

      @project.notify_subscribers({ foo: "bar" })
    end
  end

  context "#notify_metadata_subscribers" do
    test "notifies the right channel for an unlocked project" do
      expected_payload = {
        name: @project.name,
        locked: false,
        project_migration: nil,
      }
      GitHub::WebSocket.expects(:notify_project_channel).once
        .with(@project, "projects:metadata:#{@project.id}", expected_payload)

      @project.notify_metadata_subscribers
    end
  end
end
