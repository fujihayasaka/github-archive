# typed: true
# frozen_string_literal: true

require "test_helper"

module CopilotPLG
  class DomainTest < GitHub::TestCase
    include CopilotPublicUserCacheable
    include GitHub::Memoizer

    memoize def domain
      CopilotPLG::Domain.new
    end

    def self.runtime
      if GitHub.runtime.enterprise?
        :ghes
      elsif GitHub.runtime.multi_tenant_enterprise_environment?
        :proxima
      else
        :dotcom
      end
    end

    def self.in_dotcom(&block)
      if runtime == :dotcom
        context("in Dotcom", &block)
      else
        puts "Skipping dotcom because we are in #{runtime}" if TestEnv.test_queue_verbose?
      end
    end

    def self.in_ghes(&block)
      if runtime == :ghes
        context("in GHES", &block)
      else
        puts "Skipping ghes because we are in #{runtime}" if TestEnv.test_queue_verbose?
      end
    end

    def self.in_proxima(&block)
      if runtime == :proxima
        context("in Proxima", &block)
      else
        puts "Skipping proxima because we are in #{runtime}" if TestEnv.test_queue_verbose?
      end
    end

    def mock_thread_sharing_authorization(decision:, reason: nil, message: nil)
      auth = CopilotPLG::ThreadSharingAuthorization.allocate
      auth.stubs(decision:, reason:, message:)
      auth
    end

    setup do
      enable_feature_flag(:copilot_free_limited_user)
      enable_feature_flag(:copilot_share_conversation)
      enable_feature_flag(:copilot_read_shared_conversation)
    end

    context "#copilot_thread_sharing_enabled?" do
      in_dotcom do
        test "returns true" do
          assert domain.copilot_thread_sharing_enabled?
        end
      end

      in_ghes do
        test "returns false" do
          refute domain.copilot_thread_sharing_enabled?
        end
      end

      in_proxima do
        test "returns false" do
          refute domain.copilot_thread_sharing_enabled?
        end
      end
    end

    # See #authorize_thread_sharing tests for specific behaviors.
    context "#user_can_share_copilot_thread?" do
      test "returns true if the authorization decision is true" do
        user = create(:user)
        CopilotPLG::Domain.any_instance.expects(:authorize_thread_sharing).once.with(user:).
          returns(mock_thread_sharing_authorization(decision: true))

        assert domain.user_can_share_copilot_thread?(user)
      end

      test "returns false if the authorization decision is false" do
        user = create(:user)
        CopilotPLG::Domain.any_instance.expects(:authorize_thread_sharing).once.with(user:).
          returns(mock_thread_sharing_authorization(decision: false))

        refute domain.user_can_share_copilot_thread?(user)
      end

      test "accepts nil for user" do
        CopilotPLG::Domain.any_instance.expects(:authorize_thread_sharing).once.with(user: nil).
          returns(mock_thread_sharing_authorization(decision: true))

        assert domain.user_can_share_copilot_thread?(nil)
      end
    end

    context "#user_can_read_shared_copilot_thread?" do
      in_dotcom do
        test "returns false if given no user" do
          refute domain.user_can_read_shared_copilot_thread?(nil)
        end

        test "returns true for a free user with no paid affiliations" do
          user = create(:user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns false when the feature flag is disabled" do
          user = create(:user)
          disable_feature_flag(:copilot_read_shared_conversation)

          refute domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a paid user with no paid affiliations" do
          user = create(:user, :paid_plan)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user affiliated with a free GitHub organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.free)
          organization.add_member(user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user affiliated with a GitHub Team organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.business)
          organization.add_member(user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user affiliated with a legacy paid organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.bronze)
          organization.add_member(user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user affiliated with a paid enterprise via organization membership" do
          user = create(:user)
          business = create(:business)
          organization = create(:organization, business: business)
          organization.add_member(user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user affiliated with a free enterprise" do
          user = create(:user)
          business = create(:business)
          business.downgrade_to_free_plan
          organization = create(:organization, business: business)
          organization.add_member(user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for an EMU" do
          user = create(:emu)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user on the Copilot Free plan" do
          user = create(:copilot_limited_user).user
          copilot_user = Copilot::Public::User.new(user)
          assert_predicate copilot_user, :has_ci_access?
          refute_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          refute_predicate copilot_user, :has_paid_access?

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user on the Copilot Pro plan" do
          user = create(:user)
          create(:billing_subscription_item, :with_copilot_product_uuid, account: user)
          copilot_user = Copilot::Public::User.new(user)
          assert_predicate copilot_user, :has_ci_access?
          refute_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user on the Copilot Business plan" do
          user = create(:copilot_seat, copilot_plan: "business").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user on the Copilot Enterprise plan" do
          user = create(:copilot_seat, copilot_plan: "enterprise").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          assert_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a user with a Copilot Business plan on a free organization" do
          organization = create(:free_organization)
          Copilot::Organization.new(organization).enable_copilot!
          user = create(:copilot_seat, organization:, copilot_plan: "business").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a spammy user" do
          user = create(:spammy_user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for a suspended user" do
          user = create(:suspended_user)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns true for staff" do
          user = create(:user, :staff)

          assert domain.user_can_read_shared_copilot_thread?(user)
        end

        test "returns false for staff when the feature flag is disabled" do
          user = create(:user, :staff)
          disable_feature_flag(:copilot_read_shared_conversation)

          refute domain.user_can_read_shared_copilot_thread?(user)
        end
      end

      in_ghes do
        test "returns false" do
          user = create(:user)

          refute domain.user_can_read_shared_copilot_thread?(user)
        end
      end

      in_proxima do
        test "returns false" do
          user = create(:user)

          refute domain.user_can_read_shared_copilot_thread?(user)
        end
      end
    end

    context "#authorize_thread_sharing" do
      in_dotcom do
        test "is unauthorized if given no user" do
          auth = domain.authorize_thread_sharing(user: nil)

          assert_equal false, auth.decision
          assert_equal :user_is_unknown, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is authorized for a free user with no paid affiliations" do
          user = create(:user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is unauthorized when the feature flag is disabled" do
          user = create(:user)
          disable_feature_flag(:copilot_share_conversation)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_disabled, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is authorized for a paid user with no paid affiliations" do
          user = create(:user, :paid_plan)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is authorized for a user affiliated with a free GitHub organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.free)
          organization.add_member(user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is unauthorized for a user affiliated with a GitHub Team organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.business)
          organization.add_member(user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_paid_organization_membership, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is unauthorized for a user affiliated with a legacy paid organization" do
          user = create(:user)
          organization = create(:organization, plan: GitHub::Plan.bronze)
          organization.add_member(user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_paid_organization_membership, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is unauthorized for a user affiliated with a paid enterprise via organization membership" do
          user = create(:user)
          business = create(:business)
          organization = create(:organization, business: business)
          organization.add_member(user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_paid_enterprise_membership, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is authorized for a user affiliated with a free enterprise" do
          user = create(:user)
          business = create(:business)
          business.downgrade_to_free_plan
          organization = create(:organization, business: business)
          organization.add_member(user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is unauthorized for an EMU" do
          user = create(:emu)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_is_enterprise_managed, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is authorized for a user on the Copilot Free plan" do
          user = create(:copilot_limited_user).user
          copilot_user = Copilot::Public::User.new(user)
          assert_predicate copilot_user, :has_ci_access?
          refute_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          refute_predicate copilot_user, :has_paid_access?

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is authorized for a user on the Copilot Pro plan" do
          user = create(:user)
          create(:billing_subscription_item, :with_copilot_product_uuid, account: user)
          copilot_user = Copilot::Public::User.new(user)
          assert_predicate copilot_user, :has_ci_access?
          refute_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is unauthorized for a user on the Copilot Business plan" do
          user = create(:copilot_seat, copilot_plan: "business").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_business_plan, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is unauthorized for a user on the Copilot Enterprise plan" do
          user = create(:copilot_seat, copilot_plan: "enterprise").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          assert_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_enterprise_plan, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is unauthorized for a user with a Copilot Business plan on a free organization" do
          organization = create(:free_organization)
          Copilot::Organization.new(organization).enable_copilot!
          user = create(:copilot_seat, organization:, copilot_plan: "business").assigned_user
          copilot_user = Copilot::Public::User.new(user)
          refute_predicate copilot_user, :has_ci_access?
          assert_predicate copilot_user, :has_cb_access?
          refute_predicate copilot_user, :has_ce_access?
          assert_predicate copilot_user, :has_paid_access?

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :user_has_business_plan, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is sneaky unauthorized for a spammy user" do
          user = create(:spammy_user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_disabled, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is sneaky unauthorized for a suspended user" do
          user = create(:suspended_user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_disabled, auth.reason
          assert_predicate auth.message, :present?
        end

        test "is authorized for staff" do
          user = create(:user, :staff)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal true, auth.decision
          assert_equal :authorized, auth.reason
          assert_nil auth.message
        end

        test "is unauthorized for staff when the feature flag is disabled" do
          user = create(:user, :staff)
          disable_feature_flag(:copilot_share_conversation)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_disabled, auth.reason
          assert_predicate auth.message, :present?
        end
      end

      in_ghes do
        test "is unauthorized" do
          user = create(:user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_unavailable, auth.reason
          assert_predicate auth.message, :present?
        end
      end

      in_proxima do
        test "is unauthorized" do
          user = create(:user)

          auth = domain.authorize_thread_sharing(user:)

          assert_equal false, auth.decision
          assert_equal :feature_is_unavailable, auth.reason
          assert_predicate auth.message, :present?
        end
      end
    end
  end
end
