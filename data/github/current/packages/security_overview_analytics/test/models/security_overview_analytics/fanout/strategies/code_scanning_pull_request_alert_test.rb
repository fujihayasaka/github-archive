# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Fanout
    module Strategies
      class CodeScanningPullRequestAlertTest < GitHub::TestCase
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

        context ".initialize" do
          test "raises an error when tenant is a business and owner_type is not provided" do
            assert_raises(ArgumentError) { CodeScanningPullRequestAlert.new(tenant: @biz) }
          end

          test "does not raise an error when tenant is a business and owner_type is provided" do
            assert_nothing_raised { CodeScanningPullRequestAlert.new(tenant: @biz, owner_type: Types::Owner::User) }
          end

          test "does not raise an error when tenant is an organization" do
            assert_nothing_raised { CodeScanningPullRequestAlert.new(tenant: @org) }
          end

          test "does not raise an error when tenant is a user" do
            assert_nothing_raised { CodeScanningPullRequestAlert.new(tenant: @user) }
          end
        end

        context "#feature" do
          test "returns the correct feature" do
            assert_equal Types::Feature::CodeScanningPullRequestAlert, CodeScanningPullRequestAlert.new(tenant: @org).feature
          end
        end

        context "#feature_available?" do
          test "returns false when tenant is a business and owner_type is user" do
            assert_equal false, CodeScanningPullRequestAlert.new(tenant: @biz, owner_type: Types::Owner::User).feature_available?
          end

          test "returns true when tenant is a business and owner_type is organization" do
            assert_equal true, CodeScanningPullRequestAlert.new(tenant: @biz, owner_type: Types::Owner::Organization).feature_available?
          end

          test "returns true when tenant is an organization" do
            assert_equal true, CodeScanningPullRequestAlert.new(tenant: @org).feature_available?
          end

          test "returns false when tenant is a user" do
            assert_equal false, CodeScanningPullRequestAlert.new(tenant: @user).feature_available?
          end
        end

        context "#unlocked_session" do
          test "returns the initialization session when it is not locked" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            assert strategy.unlocked_session&.is_initialization?
          end

          test "returns the reconciliation session when it is not locked and the initialization session is locked" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            assert strategy.unlocked_session&.is_reconciliation?
          end

          test "returns nil when both the initialization and reconciliation sessions are locked" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            strategy.send(:reconciliation_session).lock!
            assert_nil strategy.unlocked_session
          end
        end

        context "#available_fanout_job" do
          test "returns the correct job when there's an unlocked initialization session" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            assert_equal Initialization::CodeScanningPullRequestAlertsJob, strategy.available_fanout_job(Types::Action::Initialize)
          end

          test "returns the correct job when there's an unlocked reconciliation session" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            assert_equal Reconciliation::CodeScanningPullRequestAlertsJob, strategy.available_fanout_job(Types::Action::Reconcile)
          end

          test "returns nil when the initialization session is locked" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            assert_nil strategy.available_fanout_job(Types::Action::Initialize)
          end

          test "returns nil when the reconciliation session is locked" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            strategy.send(:reconciliation_session).lock!
            assert_nil strategy.available_fanout_job(Types::Action::Reconcile)
          end
        end

        context "#lock_session!" do
          test "locks the initialization session" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            refute strategy.send(:initialization_session).locked?
            strategy.lock_session!(Types::Action::Initialize, at: Time.now)
            assert strategy.send(:initialization_session).locked?
          end

          test "locks the reconciliation session" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            strategy.send(:initialization_session).lock!
            refute strategy.send(:reconciliation_session).locked?
            strategy.lock_session!(Types::Action::Reconcile, at: Time.now)
            assert strategy.send(:reconciliation_session).locked?
          end

          test "does not lock the reconciliation session when not initialized" do
            strategy = CodeScanningPullRequestAlert.new(tenant: @org)
            refute strategy.send(:reconciliation_session).locked?
            strategy.lock_session!(Types::Action::Reconcile, at: Time.now)
            refute strategy.send(:reconciliation_session).locked?
          end
        end
      end
    end
  end
end
