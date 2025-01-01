# typed: true
# frozen_string_literal: true

require "test_helper"
module SecretScanning::Instrumentation
  class GistServiceFlagsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @gist = create(:gist, owner: @user)
    end

    setup do
      @public_scanning = SecretScanning::Features::Gist::PublicScanning.new(@gist)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Instrumentation::GistServiceFlags.new(@gist).nil?
      end
    end

    context "gist_scanning_service_flags" do
      test "empty if public scanning is disabled" do
        SecretScanning::Features::Gist::PublicScanning.any_instance.stubs(:enabled?).returns(false)

        assert_equal [], SecretScanning::Instrumentation::GistServiceFlags.new(@gist).gist_scanning_service_flags
      end

      test "all flags" do
        SecretScanning::Features::Gist::PublicScanning.any_instance.stubs(:enabled?).returns(true)

        expected_flags = %w[
          token_scanning_service_ingest
          token_scanning_service_commit_metadata_scan_enabled
        ]

        flags = SecretScanning::Instrumentation::GistServiceFlags.new(@gist).gist_scanning_service_flags
        assert_equal expected_flags, flags
      end
    end
  end
end
