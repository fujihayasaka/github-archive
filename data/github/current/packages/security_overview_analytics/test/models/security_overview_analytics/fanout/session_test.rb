# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Fanout
    class SessionTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        if GitHub.enterprise?
          @biz = create(:global_business)
          @user = create(:user, business: @biz)
        else
          @biz = create(:business, :enterprise_managed)
          @user = create(:emu, business: @biz)
        end
        @org = create(:organization, business: @biz)
      end

      context "#locked_at" do
        test "returns nil if session not locked" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          refute session.locked_at
        end

        test "returns a time after it locks" do
          now = Time.now

          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          session.lock!(at: now)

          assert_equal now.iso8601(3), session.locked_at&.iso8601(3)
        end
      end

      context "#locked?" do
        test "returns false if session not locked" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )

          refute session.locked?
        end

        test "returns true if session is locked" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          session.lock!

          assert session.locked?
        end

        test "returns true if session is locked after specified timestamp" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          session.lock!

          assert session.locked?(after: 10.days.ago)
        end

        test "returns false if session is locked before specified timestamp" do
          locked_at = 10.days.ago
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          session.lock!(at: locked_at)

          refute session.locked?(after: Time.now)
        end
      end

      context "#unlock!" do
        test "unlocks session" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          session.lock!
          assert session.locked?

          session.unlock!
          refute session.locked?
          assert_nil session.locked_at
        end
      end

      context "#is_initialization?" do
        test "returns true if action is initialize" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          assert session.is_initialization?
        end

        test "returns false if action is reconcile" do
          session = Session.new(
            action: Types::Action::Reconcile,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          refute session.is_initialization?
        end
      end

      context "#is_reconciliation?" do
        test "returns true if action is reconcile" do
          session = Session.new(
            action: Types::Action::Reconcile,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          assert session.is_reconciliation?
        end

        test "returns false if action is initialize" do
          session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: Types::TenantScope::Business,
            tenant_id: @biz.id,
            feature: Types::Feature::CodeScanningPullRequestAlert,
            feature_prerequisite: Types::Owner::Organization
          )
          refute session.is_reconciliation?
        end
      end
    end
  end
end
