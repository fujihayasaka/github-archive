# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningScanPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, owner: @org)
  end

  test "backfill scan payload" do
    now = Time.now.utc
    event = Hook::Event::SecretScanningScanEvent.new(
      repository_id: @repo.id,
      source: "SOURCE_GIT",
      source_slug: "git",
      type: "TYPE_BACKFILL",
      type_slug: "backfill",
      started_at: { "seconds" => now.to_i },
      completed_at: { "seconds" => now.to_i },
    )
    payload = Hook::Payload::SecretScanningScanPayload.new(event)

    h = payload.to_hash
    assert_equal "git", h[:source]
    assert_equal "backfill", h[:type]
    assert_equal now.xmlschema, h[:started_at]
    assert_equal now.xmlschema, h[:completed_at]
  end

  test "includes secret types for pattern update backfill" do
    event = Hook::Event::SecretScanningScanEvent.new(
      type: "TYPE_PATTERN_VERSION_BACKFILL",
      type_slug: "pattern-update-backfill",
      repository_id: @repo.id,
      source: "SOURCE_GIT",
      source_slug: "git",
      started_at: { "seconds" => Time.now.to_i },
      completed_at: { "seconds" => Time.now.to_i },
      secret_types: ["npm_access_token"],
    )
    payload = Hook::Payload::SecretScanningScanPayload.new(event)

    h = payload.to_hash
    assert_equal ["npm_access_token"], h[:secret_types]
  end

  test "includes custom pattern info for custom pattern backfill" do
    event = Hook::Event::SecretScanningScanEvent.new(
      type: "TYPE_CUSTOM_PATTERN_BACKFILL",
      type_slug: "custom-pattern-update-backfill",
      repository_id: @repo.id,
      source: "SOURCE_GIT",
      source_slug: "git",
      started_at: { "seconds" => Time.now.to_i },
      completed_at: { "seconds" => Time.now.to_i },
      custom_pattern_name: "test user defined pattern",
      custom_pattern_scope: "SCOPE_REPOSITORY",
    )
    payload = Hook::Payload::SecretScanningScanPayload.new(event)

    h = payload.to_hash
    assert_equal "test user defined pattern", h[:custom_pattern_name]
    assert_equal "repository", h[:custom_pattern_scope]
  end
end
