# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PackageRegistryPermissionTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  setup do
    disable_feature_flag(:packages_skip_billing_quotas)
    disable_feature_flag(:packages_storage_skip_usage_checks)
  end

  context "#allowed?" do
    test "allowed when plan is eligible for the GPR and the user is enabled" do
      owner = create(:user, plan: :business)

      assert Billing::PackageRegistryPermission.new(owner).allowed?
    end

    test "false if owner has metered services locked" do
      org = create(:invoiced_organization, plan: "business")
      org.lock_metered_services

      refute Billing::PackageRegistryPermission.new(org).allowed?
    end

    test "not allowed when plan is eligible for the GPR but the user is disabled" do
      owner = create(:billing_locked_user, plan: :business)

      refute Billing::PackageRegistryPermission.new(owner).allowed?
    end

    test "not allowed when the owner is enabled, but their plan is not elibible for GPR" do
      owner = create(:user, plan: :silver)

      refute Billing::PackageRegistryPermission.new(owner).allowed?
    end

    test "allowed when plan is legacy and the repo is public" do
      owner = create(:user, plan: :silver)

      assert Billing::PackageRegistryPermission.new(owner).allowed?(public: true)
    end

    test "not allowed when plan is legacy and repo is private" do
      owner = create(:user, plan: :silver)

      refute Billing::PackageRegistryPermission.new(owner).allowed?(public: false)
    end

    test "false if the user is a fully trade restricted organization" do
      org = build(:organization, :fully_trade_restricted, plan: "business")

      refute Billing::PackageRegistryPermission.new(org).allowed?
    end
  end

  context "#status" do
    test "returns true without running any queries for `github`" do
      org = build(:organization, login: "github")
      permissions = Billing::PackageRegistryPermission.new(org)

      assert_no_queries do
        assert permissions.allowed?
      end
    end

    test "allowed when plan is eligible for the GPR and the user is enabled" do
      owner = create(:user, plan: :business)

      result = Billing::PackageRegistryPermission.new(owner).status

      assert result[:allowed]
      assert_empty result[:error]
    end

    test "allowed is false if the user has metered services locked" do
      org = create(:invoiced_organization, plan: "business")
      org.lock_metered_services
      status = Billing::PackageRegistryPermission.new(org).status

      refute status[:allowed]
      assert_equal "METERED_SERVICES_LOCKED", status[:error][:reason]
    end

    test "not allowed when plan is eligible for the GPR but the user is disabled" do
      owner = create(:billing_locked_user, plan: :business)

      result = Billing::PackageRegistryPermission.new(owner).status

      refute result[:allowed]
      assert_equal Hash[reason: "DISABLED", message: "Account must be enabled to use the GitHub Package Registry"], result[:error]
    end

    test "not allowed when the owner is enabled, but their plan is not elibible for GPR and the package is private" do
      owner = create(:user, plan: :silver)

      result = Billing::PackageRegistryPermission.new(owner).status

      refute result[:allowed]
      assert_equal Hash[reason: "PLAN_INELIGIBLE", message: "Legacy billing plans can't use GitHub Package Registry"], result[:error]
    end

    test "allowed when the owner is enabled, but their plan is not elibible for GPR and the package is public" do
      owner = create(:user, plan: :silver)

      assert Billing::PackageRegistryPermission.new(owner).allowed?(public: true)
    end

    test "allowed is false if they are a fully trade controls restricted org" do
      org = build(:organization, :fully_trade_restricted, plan: "business")

      refute Billing::PackageRegistryPermission.new(org).allowed?
      status = Billing::PackageRegistryPermission.new(org).status

      refute status[:allowed]
      assert_equal "TRADE_RESTRICTED_ORGANIZATION", status[:error][:reason]
      assert_equal TradeControls::Notices.notice_as_plaintext(:org_restricted), status[:error][:message]
    end
  end

  context "#download_allowed?" do
    test "returns true when metered billing permission check is skipped for the user" do
      owner = create(:user)

      owner.skip_metered_billing_permission_check_for(product: :packages)

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns true when packages_skip_billing_quotas ff enabled for the user" do
      owner = create(:user)

      enable_feature_flag(:packages_skip_billing_quotas, owner)
      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns true without running any queries for `github`" do
      org = build(:organization, login: "github")
      permissions = Billing::PackageRegistryPermission.new(org)

      assert_no_queries do
        assert permissions.download_allowed?(bytes: 100_000, public: false)
      end
    end

    test "returns false if fully trade restricted organization is the owner" do
      org = build(:organization, :fully_trade_restricted, plan: "business")
      permissions = Billing::PackageRegistryPermission.new(org)
      refute permissions.download_allowed?(bytes: 0, public: true)
      refute permissions.download_allowed?(bytes: 0, public: false)
    end

    test "returns false when private repo download for trade restricted user" do
      user = build(:user, :fully_trade_restricted, plan: "pro")
      permissions = Billing::PackageRegistryPermission.new(user)
      assert permissions.download_allowed?(bytes: 0, public: true)
      refute permissions.download_allowed?(bytes: 0, public: false)
    end

    test "returns false when private repo download for partially trade restricted org" do
      org = build(:organization, :partially_trade_restricted, plan: "business")
      permissions = Billing::PackageRegistryPermission.new(org)
      assert permissions.download_allowed?(bytes: 0, public: true)
      refute permissions.download_allowed?(bytes: 0, public: false)
    end

    test "return true for public when owner has a legacy plan" do
      owner = create(:user, plan: :silver)

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: true)
    end

    test "return false for private when owner has a legacy plan" do
      owner = create(:user, plan: :silver)

      refute Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns true if public" do
      owner = create(:user)
      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      refute Billing::PackageRegistryPermission.new(org).download_allowed?(bytes: 1, public: false)
    end

    test "returns true for public usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      assert Billing::PackageRegistryPermission.new(org).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      refute Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: false)
    end

    test "returns true for public usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      assert Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for public usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::PackageRegistryPermission.new(org).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::PackageRegistryPermission.new(org).download_allowed?(bytes: 1, public: false)
    end

    test "returns false for public usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: false)
    end

    test "returns false for public usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::PackageRegistryPermission.new(business).download_allowed?(bytes: 1, public: false)
    end

    test "returns true if private and bytes can fit in included bandwidth" do
      owner = create(:user)
      mock_get_usage_breakdown_for_packages(owner: owner, available_download_gigabytes: 1, available_storage_megabytes: 0, available_spending_limit: 0)

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1000000457, public: false)
    end

    test "returns false if private and bytes can not fit in included bandwidth and metered billing permission usage not allowed" do
      owner = create(:user)
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns true if private and metered billing permission usage allowed" do
      owner = create(:credit_card_user)
      mock_get_usage_breakdown_for_packages(owner: owner, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 1)

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns false when all included bandwidth is consumed with 2 billing attempts" do
      owner = create(:user, billing_attempts: 2)
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "returns true when not all included bandwidth is consumed with 2 billing attempts" do
      owner = create(:user, billing_attempts: 2)
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0.5, available_storage_megabytes: 0, available_spending_limit: 0)

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end

    test "passes bytes to PackageRegistryUsage.usage_quote" do
      owner = create(:user)
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)


      Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1073741824, public: false)
    end

    test "returns true when billing api returns error" do
      owner = create(:user)
      mock_get_usage_breakdown_response_error

      assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
    end
  end

  context "#storage_allowed?" do
    test "returns true when metered billing permission check is skipped for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner: owner, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)

      owner.skip_metered_billing_permission_check_for(product: :storage)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true when packages_skip_billing_quotas ff enabled for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)

      enable_feature_flag(:packages_skip_billing_quotas, owner)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true without running any queries for `github`" do
      org = build(:organization, login: "github")
      permissions = Billing::PackageRegistryPermission.new(org)

      assert_no_queries do
        assert permissions.storage_allowed?(bytes: 100_000, public: false)
      end
    end

    test "returns false if fully trade restricted organization is the owner" do
      org = build(:organization, :fully_trade_restricted, plan: "business")
      permissions = Billing::PackageRegistryPermission.new(org)
      refute permissions.storage_allowed?(bytes: 0, public: true)
      refute permissions.storage_allowed?(bytes: 0, public: false)
    end

    test "returns false when private repo storage for trade restricted user" do
      user = build(:user, :fully_trade_restricted, plan: "pro")
      permissions = Billing::PackageRegistryPermission.new(user)
      assert permissions.storage_allowed?(bytes: 0, public: true)
      refute permissions.storage_allowed?(bytes: 0, public: false)
    end

    test "returns false when private repo storage for partially trade restricted org" do
      org = build(:organization, :partially_trade_restricted, plan: "business")
      permissions = Billing::PackageRegistryPermission.new(org)
      assert permissions.storage_allowed?(bytes: 0, public: true)
      refute permissions.storage_allowed?(bytes: 0, public: false)
    end

    test "returns true if public" do
      owner = create(:user)
      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: true)
    end

    test "return true for public when owner has a legacy plan" do
      owner = create(:user, plan: :silver)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      refute Billing::PackageRegistryPermission.new(org).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true for public usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      assert Billing::PackageRegistryPermission.new(org).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      refute Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true for public usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      assert Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for public usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::PackageRegistryPermission.new(org).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::PackageRegistryPermission.new(org).storage_allowed?(bytes: 1, public: false)
    end

    test "returns false for public usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: false)
    end

    test "returns false for public usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: true)
    end

    test "returns false for private usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::PackageRegistryPermission.new(business).storage_allowed?(bytes: 1, public: false)
    end

    test "return false for private when owner has a legacy plan" do
      owner = create(:user, plan: :silver)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true if private usage is under included megabytes" do
      owner = create(:user)
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 1, available_spending_limit: 0)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns false if private usage is over included megabytes and metered billing usage is not allowed" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)


      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true if private and metered billing permission usage allowed" do
      owner = create(:credit_card_user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      # 1024mb + 1 addional * max of 744 hours remaining in the month = 762,600 addional mb hours
      # 762,600 * 0.000000328 = $0.2501328 budget needed
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 26)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true for business if private and metered billing permission usage allowed" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      org.reload
      business.reload
      Business.any_instance.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 75GB used / 50 included GB / Unlimited spending limit by default for business
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 75.gigabytes,
        owner: org, billable_owner: business,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner: business, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: nil)


      assert Billing::PackageRegistryPermission.new(org).storage_allowed?(bytes: 1, public: false)
    end

    test "returns false if private and metered billing permission usage not allowed" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns false when all included private storage is consumed with 2 billing attempts" do
      owner = create(:user, billing_attempts: 2)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      included_storage_bytes = owner.plan.shared_storage_included_megabytes.megabytes
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: included_storage_bytes + 100.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true when not all included private storage is consumed with 2 billing attempts" do
      owner = create(:user, billing_attempts: 2)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      included_storage_bytes = owner.plan.shared_storage_included_megabytes.megabytes
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: included_storage_bytes - 100.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: included_storage_bytes / 1.megabyte * 744, available_spending_limit: 0)


      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true when billing api returns error" do
      owner = create(:user)
      mock_get_usage_breakdown_response_error

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end

    test "returns true when packages_storage_skip_usage_checks ff enabled for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)
      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_packages(owner:, available_download_gigabytes: 0, available_storage_megabytes: 0, available_spending_limit: 0)

      refute Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)

      enable_feature_flag(:packages_storage_skip_usage_checks, owner)

      assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
    end
  end
end if GitHub.billing_enabled?
