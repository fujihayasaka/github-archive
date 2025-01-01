# typed: true
# frozen_string_literal: true

require "test_helper"

class PreReceiveEnvironmentTest < GitHub::TestCase
  fixtures do
    create(:pre_receive_environment, id: 1, name: "Default", image_url: "githubenterprise://internal", checksum: "0")
  end

  setup do
    @deleteme = []
  end

  teardown do
    require "fileutils"
    while dir = @deleteme.shift
      FileUtils.rm_rf dir
    end
  end

  test "requires a name" do
    environment = PreReceiveEnvironment.new image_url: "http://example.com"
    assert !environment.valid?
    environment.name = "name"
    assert environment.valid?
  end

  test "requires an image_url" do
    environment = PreReceiveEnvironment.new name: "environment name"
    assert !environment.valid?
    environment.image_url = "http://example.com"
    assert environment.valid?
  end

  test "requires an image_url of the correct length" do
    environment = build :pre_receive_environment, name: "test env", image_url: "http://#{"e" * 255}xample.com"
    refute_predicate environment, :valid?
    assert_includes environment.errors[:image_url], "is too long (maximum is 255 characters)"
  end

  test "name must be unique" do
    PreReceiveEnvironment.create name: "name", image_url: "http://example.com"

    environment = PreReceiveEnvironment.new name: "name", image_url: "http://example.com"
    refute environment.save, "Must have a unique name"

    environment.name = "NAME"
    refute environment.save, "Uniqueness should not be case sensitive"

    environment.name = "another name"
    assert environment.save, "Should have saved because name is unique"
  end

  test "responds to hooks" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    assert_equal 0, environment.hooks.count
    hook1 = create :pre_receive_hook, environment: environment
    hook2 = create :pre_receive_hook, environment: environment
    assert_equal 2, environment.hooks.count
    assert_equal [hook1, hook2].sort, environment.hooks.sort
  end

  test "creates an audit log entry on create" do
    events = subscribe "pre_receive_environment.create"
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"

    expected_payload = {
      pre_receive_environment: "name",
      pre_receive_environment_id: environment.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on update" do
    events = subscribe "pre_receive_environment.update"
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    environment.name = "other"
    environment.save

    expected_payload = {
      pre_receive_environment: "other",
      pre_receive_environment_id: environment.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on destroy" do
    events = subscribe "pre_receive_environment.destroy"
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    environment.destroy

    expected_payload = {
      pre_receive_environment: "name",
      pre_receive_environment_id: environment.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "cannot delete environment that has hooks" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    hook = create :pre_receive_hook, environment: environment
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      environment.destroy
    end
    hook.destroy
    assert environment.destroy
  end

  test "start_download" do
    environment = PreReceiveEnvironment
                      .create name: "name",
                              image_url: "http://example.com",
                              download_message: "foo"

    start_time = Time.current
    environment.start_download start_time
    assert_same_time start_time, environment.downloaded_at
    assert_predicate environment, :in_progress?
    assert_nil environment.download_message
  end

  test "download_failed" do
    environment = PreReceiveEnvironment
                      .create name: "name",
                              image_url: "http://example.com"
    start_time = Time.current
    environment.start_download start_time
    failure_message = "this is a download failure message"
    environment.download_failed failure_message
    assert_same_time start_time, environment.downloaded_at
    assert_predicate environment, :failed?
    assert_equal failure_message, environment.download_message
  end

  test "queue download" do
    test_tar = RUBY_PLATFORM =~ /darwin/ ? "osx-hook-env-1.tar.gz" : "hook-env-1.tar.gz"
    url = File.expand_path("test/fixtures/pre_receive_hook/#{test_tar}")
    checksum = if RUBY_PLATFORM =~ /darwin/
      "363f400950b96835574c593294faaf4dde202b56ecc4a6edb51268fd3849b764"
    else
      "8f9abcc47f82e7fb810660ebd9794bab869044a4169f9989002c19e0ca5894b2"
    end
    environment = PreReceiveEnvironment
                      .new name: "name",
                              image_url: url
    @deleteme = [
        File.expand_path("git-hooks/environments/#{environment.id}"),
        File.expand_path("git-hooks/environments/tarballs/#{environment.id}"),
    ]
    perform_enqueued_jobs(only: [PreReceiveEnvironmentDownloadJob]) do
      environment.save
    end
    environment.reload
    assert_equal checksum, environment.checksum
    assert environment.download_succeeded?
    assert File.exist? "git-hooks/environments/#{environment.id}"
    assert File.exist? "git-hooks/environments/tarballs/#{environment.id}"
  end

  test "queue download only when not already in progress" do
    test_tar = RUBY_PLATFORM =~ /darwin/ ? "osx-hook-env-1.tar.gz" : "hook-env-1.tar.gz"
    url = File.expand_path("test/fixtures/pre_receive_hook/#{test_tar}")
    environment = PreReceiveEnvironment
                      .new name: "name",
                              image_url: url,
                              download_state: :in_progress
    environment.save

    environment.reload
    assert_nil environment.checksum
    assert environment.download_in_progress?
  end

  test "doesn't allow changing image_url when download is in progress" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    environment.start_download Time.now
    environment.update image_url: "http://new-image.com"
    assert_equal "http://example.com", environment.reload.image_url
    environment.download_failed
    environment.update image_url: "http://new-image.com"
    assert_equal "http://new-image.com", environment.reload.image_url
  end

  context "download_display_message" do
    test "when download failed" do
      env = create :pre_receive_environment, download_state: :failed, download_message: "Unable to connect to Url."
      assert_equal "Download failed. Unable to connect to Url.", env.download_display_message
    end

    test "when download succeeded" do
      env = create :pre_receive_environment, download_state: :success
      assert_equal "Environment downloaded and ready", env.download_display_message
    end

    test "when download not started" do
      env = create :pre_receive_environment, download_state: :not_started
      assert_equal "Download has not started", env.download_display_message
    end

    test "when download in progress" do
      env = create :pre_receive_environment, download_state: :in_progress
      assert_equal "Download is in progress", env.download_display_message
    end
  end

  test "syncs download state when download states changes" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    environment.expects(:sync_download_state).once
    environment.update!(download_state: :success)
  end

  test "does not syncs download state when download states is not changed" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com"
    environment.expects(:sync_download_state).never
    environment.update!(name: "some other name")
  end


  test "can not destroy if download in progress" do
    environment = PreReceiveEnvironment.create name: "name", image_url: "http://example.com", download_state: :in_progress
    assert !environment.destroy
    environment.update(download_state: :success)
    assert environment.destroy
  end

  test "can not edit default environment" do
    environment = PreReceiveEnvironment.default
    environment.name = "other"
    refute environment.save, "environment should be allowed to be updated"
  end

  test "can not destroy default environment" do
    refute PreReceiveEnvironment.default.destroy, "environment should not be allowed to be destroyed"
  end

  test "does not remove environment from filesystem on destroy attempt" do
    default = PreReceiveEnvironment.default
    default.expects(:queue_delete_from_filesystem).never
    default.destroy
  end
end
