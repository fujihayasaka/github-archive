# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerWikiScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
    end

    setup do
      @wiki_scanning_user = SecretScanning::Features::Owner::WikiScanning.new(@user)
      @wiki_scanning_org = SecretScanning::Features::Owner::WikiScanning.new(@org)
      @wiki_scanning_biz = SecretScanning::Features::Owner::WikiScanning.new(@business)
    end

    context "initialize" do
      test "good input for any type of owner" do
        [@user, @org, @business].each do |owner|
          refute SecretScanning::Features::Owner::WikiScanning.new(owner).nil?
        end
      end
    end

    context "user-level feature_available?" do
      test "true if public scanning enabled", skip_enterprise: true do
        SecretScanning::Features::User::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::User::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        assert @wiki_scanning_user.feature_available?
      end

      test "true if token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::User::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::User::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @wiki_scanning_user.feature_available?
      end

      test "false if neither public nor token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::User::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::User::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @wiki_scanning_user.feature_available?
      end

      test "false on GHES", enterprise_only: true do
        SecretScanning::Features::User::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::User::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        refute @wiki_scanning_user.feature_available?
      end
    end

    context "org-level feature_available?" do
      test "true if public scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Org::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        assert @wiki_scanning_org.feature_available?
      end

      test "true if token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Org::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @wiki_scanning_org.feature_available?
      end

      test "false if neither public nor token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Org::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @wiki_scanning_org.feature_available?
      end

      test "false on GHES", enterprise_only: true do
        SecretScanning::Features::Org::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        refute @wiki_scanning_org.feature_available?
      end
    end

    context "business-level feature_available?" do
      test "true if public scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        assert @wiki_scanning_biz.feature_available?
      end

      test "true if token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @wiki_scanning_biz.feature_available?
      end

      test "false if neither public nor token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @wiki_scanning_biz.feature_available?
      end

      test "false on GHES", enterprise_only: true do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        refute @wiki_scanning_biz.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available and feature flags are enabled" do
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)

        assert @wiki_scanning_user.enabled?
        assert @wiki_scanning_org.enabled?
        assert @wiki_scanning_biz.enabled?
      end

      test "false if feature not available" do
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:feature_available?).returns(false)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)

        refute @wiki_scanning_user.enabled?
        refute @wiki_scanning_org.enabled?
        refute @wiki_scanning_biz.enabled?
      end

      test "false if incremental scan feature flag not enabled" do
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(false)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)

        refute @wiki_scanning_user.enabled?
        refute @wiki_scanning_org.enabled?
        refute @wiki_scanning_biz.enabled?
      end

      test "false if backfill scan feature flag not enabled" do
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(false)

        refute @wiki_scanning_user.enabled?
        refute @wiki_scanning_org.enabled?
        refute @wiki_scanning_biz.enabled?
      end

      test "false on enterprise", enterprise_only: true do
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)

        refute @wiki_scanning_user.enabled?
        refute @wiki_scanning_org.enabled?
        refute @wiki_scanning_biz.enabled?
      end
    end
  end
end
