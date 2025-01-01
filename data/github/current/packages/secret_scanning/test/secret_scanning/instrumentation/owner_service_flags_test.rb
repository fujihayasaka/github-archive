# typed: true
# frozen_string_literal: true

require "test_helper"
module SecretScanning::Instrumentation
  class OwnerServiceFlagsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @org = create(:organization, login: "org")
      @github = create(:organization, login: "github")
      @actor = create(:user)
    end

    setup do
      SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:scan_all_token_types_enabled?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:historical_backfill_scan_enabled?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Instrumentation::OwnerServiceFlags.new(@org).nil?
      end
    end

    context "group_backfill_service_flags" do
      test "empty if no scanning is enabled" do
        SecretScanning::Features::Owner::ContentScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:enabled?).returns(false)

        assert_equal [], SecretScanning::Instrumentation::OwnerServiceFlags.new(@org).group_backfill_service_flags
      end

      test "includes corresponding service flags for enabled scanning services" do
        SecretScanning::Features::Owner::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:enabled?).returns(true)

        expected_flags = [
          ServiceFlags::CONTENT_BACKFILL_SCAN,
          ServiceFlags::WIKI_INCREMENTAL_SCANS,
          ServiceFlags::WIKI_BACKFILL_SCANS,
        ]

        assert_equal expected_flags, SecretScanning::Instrumentation::OwnerServiceFlags.new(@org).group_backfill_service_flags
      end
    end
  end
end
