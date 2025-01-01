# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSecretScanningScanEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, owner: @org)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
    GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :source
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :source_slug
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :type
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :type_slug
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :started_at
    assert_event_required_attributes Hook::Event::SecretScanningScanEvent, :completed_at
  end

  test "target_repository" do
    event = Hook::Event::SecretScanningScanEvent.new(
      repository_id: @repo.id,
      source: :SOURCE_GIT,
      source_slug: "git",
      type: :TYPE_BACKFILL,
      type_slug: "backfill",
      started_at: Time.now.utc.iso8601.to_s,
      completed_at: Time.now.utc.iso8601.to_s,
    )
    assert_equal @repo, event.target_repository
  end

  context "deliverable?" do
    test "false if no repo is found" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_BACKFILL,
        type_slug: "backfill",
        repository_id: 0,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )

      refute_predicate event, :deliverable?
    end

    test "true if repo is found" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_BACKFILL,
        type_slug: "backfill",
        repository_id: @repo.id,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )

      assert_predicate event, :deliverable?
    end
  end

  context "pattern_update_backfill?" do
    test "true if type is pattern_update_backfill" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_PATTERN_VERSION_BACKFILL,
        type_slug: "pattern-update-backfill",
        repository_id: @repo.id,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )
      assert_predicate event, :pattern_update_backfill?
    end

    test "false if type is not pattern_update_backfill" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_BACKFILL,
        type_slug: "backfill",
        repository_id: @repo.id,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )
      refute_predicate event, :pattern_update_backfill?
    end
  end

  context "custom_pattern_backfill?" do
    test "true if type is custom_pattern_backfill" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_CUSTOM_PATTERN_BACKFILL,
        type_slug: "custom-pattern-update-backfill",
        repository_id: @repo.id,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )
      assert_predicate event, :custom_pattern_backfill?
    end

    test "false if type is not custom_pattern_backfill" do
      event = Hook::Event::SecretScanningScanEvent.new(
        type: :TYPE_BACKFILL,
        type_slug: "backfill",
        repository_id: @repo.id,
        source: :SOURCE_GIT,
        source_slug: "git",
        started_at: Time.now.utc.iso8601.to_s,
        completed_at: Time.now.utc.iso8601.to_s,
      )
      refute_predicate event, :custom_pattern_backfill?
    end
  end
end
