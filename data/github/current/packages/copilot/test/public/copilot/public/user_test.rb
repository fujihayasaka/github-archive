# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotPublicUserTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include CopilotPublicUserCacheable

  setup do
    GitHub.flipper[:copilot_extensibility_policy_override].disable
    GitHub.flipper[:copilot_dotcom_chat_ci_and_cb].enable
  end

  fixtures do
    @no_copilot_user = create(:user)

    seat = create(:copilot_seat)
    @cfb_user = seat.assigned_user

    @free_user = create(:user)
    create(
      :copilot_free_user,
      user: @free_user,
      subscribed: true,
      free_user_type: Copilot::FreeUser::COMPLIMENTARY_ACCESS.name,
      last_checked_date: Date.new(9999, 12, 31),
    )

    @free_limited_user = create(:copilot_limited_user).user
    GitHub.flipper[:copilot_free_limited_user].enable(@free_limited_user)

    copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    plan_subscription = create(:billing_plan_subscription, :zuora)
    @cfi_trial_user = plan_subscription.user
    create(:billing_subscription_item, :paid,
      plan_subscription: plan_subscription,
      subscribable: copilot_monthly_product_uuid,
      free_trial_ends_on: 10.days.from_now
    )

    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
    @copilot_monthly_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze
    @copilot_yearly_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year).freeze
    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @cfi_user = @plan_subscription.user
    Billing::Public::SubscriptionItem.create(
      product: @copilot_monthly_product_identifier,
      account: @cfi_user,
      actor: @cfi_user,
      free_trial_length: 0.days
    )
  end

  context "access type and plan" do
    test "when user has no plan" do
      user = create(:user)

      public_user = Copilot::Public::User.new(user)
      assert_equal public_user.access_type, :NO_ACCESS
      refute public_user.has_ci_access?
      refute public_user.has_cb_access?
      refute public_user.has_ce_access?
      refute public_user.has_free_pro_access?
      refute public_user.has_paid_access?
      refute public_user.has_trial_access?
      refute public_user.has_copilot_access?
      refute public_user.has_limited_access?
    end

    test "when user has a paid copilot individual plan" do
      public_user = Copilot::Public::User.new(@cfi_user)
      assert_equal public_user.access_type, :MONTHLY_SUBSCRIBER
      assert public_user.has_ci_access?
      refute public_user.has_cb_access?
      refute public_user.has_ce_access?
      refute public_user.has_free_pro_access?
      assert public_user.has_paid_access?
      refute public_user.has_trial_access?
      assert public_user.has_copilot_access?
      refute public_user.has_limited_access?
      assert public_user.user_feedback_opt_in_enabled?
    end

    test "when user has a trial copilot individual plan" do
      public_user = Copilot::Public::User.new(@cfi_trial_user)
      assert_equal public_user.access_type, :TRIAL_30_MONTHLY_SUBSCRIBER
      assert public_user.has_ci_access?
      refute public_user.has_cb_access?
      refute public_user.has_ce_access?
      refute public_user.has_free_pro_access?
      refute public_user.has_paid_access?
      assert public_user.has_trial_access?
      assert public_user.has_copilot_access?
      refute public_user.has_limited_access?
    end

    test "when user has a free copilot individual plan" do
      public_user = Copilot::Public::User.new(@free_user)
      assert_equal public_user.access_type, :COMPLIMENTARY_ACCESS
      assert public_user.has_ci_access?
      refute public_user.has_cb_access?
      refute public_user.has_ce_access?
      assert public_user.has_free_pro_access?
      refute public_user.has_paid_access?
      refute public_user.has_trial_access?
      assert public_user.has_copilot_access?
      refute public_user.has_limited_access?
    end

    test "when user has a free limited copilot plan" do
      public_user = Copilot::Public::User.new(@free_limited_user)
      assert_equal public_user.access_type, :FREE_LIMITED_COPILOT
      assert public_user.has_ci_access?
      refute public_user.has_cb_access?
      refute public_user.has_ce_access?
      refute public_user.has_free_pro_access?
      refute public_user.has_paid_access?
      refute public_user.has_trial_access?
      assert public_user.has_copilot_access?
      assert public_user.has_limited_access?
    end

    test "for users with standalone orgs, returns business if no org has an enterprise plan" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      assert_equal public_user.access_type, :COPILOT_FOR_BUSINESS_SEAT
      assert public_user.has_cb_access?
    end

    test "for users with enterprise-owned orgs, returns business if no org has an enterprise plan" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, business: business)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      assert_equal public_user.access_type, :COPILOT_FOR_BUSINESS_SEAT
      assert public_user.has_cb_access?
    end

    test "for users with enterprise-owned orgs, returns enterprise if the business has an enterprise plan" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, business: business)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).copilot_plan_enterprise!

      public_user = Copilot::Public::User.new(user)
      assert_equal public_user.access_type, :COPILOT_ENTERPRISE_SEAT
      assert public_user.has_ce_access?
    end
  end


  context "org and enterprise counts" do
    test "has two orgs and two enterprises" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_no_policy!

      public_user = Copilot::Public::User.new(user)
      assert_equal public_user.organization_ids.count, 2
      assert_equal public_user.business_ids.count, 2
      assert_equal public_user.organization_ids.first, org1.id
      assert_equal public_user.organization_ids.second, org2.id
      assert_equal public_user.business_ids.first, biz1.id
      assert_equal public_user.business_ids.second, biz2.id
    end
  end

  context "copilot_for_business_enabled?" do
    test "always false for blank users" do
      user = Copilot::Public::User.new(create(:user))

      refute user.has_cb_access?
      refute user.has_ce_access?
    end

    test "returns true for cfb users" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::Public::User.new(user)
      assert copilot_user.has_cb_access?
    end

    test "returns true for cfb standalone users" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats

      seat = seat_assignment.seats.first
      user = seat.assigned_user

      copilot_user = Copilot::Public::User.new(user)
      assert copilot_user.has_cb_access?
    end if TestEnv.test_with_all_emus?
  end

  context "CFI" do
    context "public code suggestions" do
      test "user defaults to public code suggestions disabled" do
        copilot_user = Copilot::Public::User.new(@cfi_user)
        refute copilot_user.public_code_suggestions_enabled?
      end

      test "disabling public code suggestions" do
        copilot_user = Copilot::User.new(@cfi_user)
        copilot_user.block_public_code_suggestions!
        public_copilot_user = Copilot::Public::User.new(@cfi_user)
        refute public_copilot_user.public_code_suggestions_enabled?
      end

      test "enabling code suggestions" do
        copilot_user = Copilot::User.new(@cfi_user)
        copilot_user.allow_public_code_suggestions!
        copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
        public_copilot_user = Copilot::Public::User.new(@cfi_user)
        assert public_copilot_user.public_code_suggestions_enabled?
      end

      test "ide chat enabled" do
        copilot_user = Copilot::Public::User.new(@cfi_user)
        assert copilot_user.ide_chat_enabled?
      end
    end
  end

  context "multiple organizations" do
    test "chat enabled if part of multiple organizations and at least one is enabled" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      assert public_user.ide_chat_enabled?
    end

    test "chat disabled if part of multiple organizations and none are enabled" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      refute public_user.ide_chat_enabled?
    end

    test "chat disabled if part of multiple enterprises and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).enable_chat!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).disable_chat!

      public_user = Copilot::Public::User.new(user)
      refute public_user.ide_chat_enabled?
    end

    test "chat enabled if part of multiple organizations and one is enabled and one is not configured" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      assert public_user.ide_chat_enabled?
    end

    test "chat enabled if part of multiple organizations and all are allowed" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).enable_chat!

      public_user = Copilot::Public::User.new(user)
      assert public_user.ide_chat_enabled?
    end

    test "chat disabled if part of multiple enterprises and organizations and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).enable_chat!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).disable_chat!

      public_user = Copilot::Public::User.new(user)
      refute public_user.ide_chat_enabled?
    end
  end

  context "CLI settings" do
    test "CLI enabled if part of multiple organizations and one is enabled and one is not configured" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).cli_enabled!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      user.reload
      assert Copilot::User.new(user).cli_enabled?
    end

    test "CLI enabled if part of multiple organizations and all are allowed" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).cli_enabled!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).cli_enabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.cli_enabled?
    end

    test "CLI disabled if part of multiple enterprises and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).cli_enabled!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).cli_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.cli_enabled?
    end

    test "CLI enabled if part of multiple enterprises but has a seat in only one of them" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).cli_enabled!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      copilot_business = Copilot::Business.new(business2)
      copilot_business.enable_copilot_for_all_organizations!
      copilot_business.cli_disabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.cli_enabled?
    end

    test "CLI enabled if user is just a CFI user" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      copilot_user = Copilot::User.new(user)
      assert copilot_user.has_cfi_access?

      public_user = Copilot::Public::User.new(user)
      refute public_user.cli_enabled?
    end

    context "when disabled" do
      test "and user does not have copilot at all" do
        user = create(:user)
        public_user = Copilot::Public::User.new(user)

        refute public_user.cli_enabled?
      end

      test "and a member of any business in which the user has a seat has cli disabled" do
        business = create(:business)
        user = create(:user)
        org = create(:business_organization)
        business.add_organization org
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).cli_disabled!

        business2 = create(:business)
        org2 = create(:business_organization)
        org2.add_member user
        business2.add_organization org2
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Business.new(business2).cli_enabled!

        public_user = Copilot::Public::User.new(user)
        refute public_user.cli_enabled?
      end

      test "only evaluates business in which the user has a seat" do
        business = create(:business)
        user = create(:user)
        org = create(:business_organization)
        business.add_organization org
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).cli_disabled!

        business2 = create(:business)
        org2 = create(:business_organization)
        org2.add_member user
        business2.add_organization org2
        copilot_business = Copilot::Business.new(business2)
        copilot_business.enable_copilot_for_all_organizations!
        copilot_business.cli_enabled!

        public_user = Copilot::Public::User.new(user)
        refute public_user.cli_enabled?
      end

      test "is not disabled when user is a member of multiple orgs and one is disabled" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).cli_enabled!

        org2 = create(:business_organization)
        org2.add_member user
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Organization.new(org2).cli_disabled!

        public_user = Copilot::Public::User.new(user)
        assert public_user.cli_enabled?
      end

      test "and a member of multiple orgs and all are disabled" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).cli_disabled!

        org2 = create(:business_organization)
        org2.add_member user
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Organization.new(org2).cli_disabled!

        public_user = Copilot::Public::User.new(user)
        refute public_user.cli_enabled?
      end
    end
  end

  context "#copilot_for_dotcom" do
    test "is true when cfi user" do
      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.dotcom_chat_enabled?
      assert public_user.pr_summarizations_enabled?
      assert public_user.copilot_for_dotcom_enabled?
    end
  end

  context "#dotcom_chat_enabled?" do
    context "when free" do
      test "is true" do
        user = create(:user)
        create(:copilot_free_user, user: user, subscribed: true)
        public_user = Copilot::Public::User.new(user)
        assert public_user.dotcom_chat_enabled?
      end
    end
  end

  context "#copilot_for_dotcom_enabled?" do
    context "when part of a disabled business" do
      test "is false" do
        business = create(:business)
        org = create(:organization, business: business)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).copilot_for_dotcom_disabled!
        public_user = Copilot::Public::User.new(user)
        refute public_user.dotcom_chat_enabled?
        refute public_user.pr_summarizations_enabled?
        refute public_user.copilot_for_dotcom_enabled?
      end
    end

    context "when no business disables it and an org enables it" do
      test "is true" do
        business = create(:business)
        org = create(:organization, business: business)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).copilot_for_dotcom_no_policy!
        public_user = Copilot::Public::User.new(user)
        assert public_user.dotcom_chat_enabled?
        assert public_user.pr_summarizations_enabled?
        assert public_user.copilot_for_dotcom_enabled?
      end
    end

    context "when orgs disable it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)
        public_user = Copilot::Public::User.new(user)
        refute public_user.dotcom_chat_enabled?
        refute public_user.pr_summarizations_enabled?
        refute public_user.copilot_for_dotcom_enabled?
      end
    end

    context "when not part of an org" do
      test "references the user config" do
        user = create(:user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)
        public_user = Copilot::Public::User.new(user)
        refute public_user.dotcom_chat_enabled?
        refute public_user.pr_summarizations_enabled?
        refute public_user.copilot_for_dotcom_enabled?
      end
    end
  end

  context "copilot_for_dotcom_enabled!" do
    test "updates each dotcom feature in the user's config" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)

      copilot_user.copilot_for_dotcom_enabled!
      public_user = Copilot::Public::User.new(user)
      assert public_user.dotcom_chat_enabled?
      assert public_user.pr_summarizations_enabled?
      assert public_user.copilot_for_dotcom_enabled?
    end
  end

  context "#copilot_for_dotcom_disabled?" do
    context "when part of a disabled organization" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        refute public_user.dotcom_chat_enabled?
        refute public_user.pr_summarizations_enabled?
        refute public_user.copilot_for_dotcom_enabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        assert public_user.dotcom_chat_enabled?
        assert public_user.pr_summarizations_enabled?
        assert public_user.copilot_for_dotcom_enabled?
      end
    end

    context "when not part of an org" do
      test "references the user config" do
        user = create(:user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        refute public_user.dotcom_chat_enabled?
        refute public_user.pr_summarizations_enabled?
        refute public_user.copilot_for_dotcom_enabled?
      end
    end
  end

  context "copilot_for_dotcom_disabled!" do
    test "updates each dotcom feature in the user's config" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)

      copilot_user.copilot_for_dotcom_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.dotcom_chat_enabled?
      refute public_user.pr_summarizations_enabled?
      refute public_user.copilot_for_dotcom_enabled?
    end
  end

  context "dotcom_chat_enabled!" do
    test "updates each dotcom feature in the user's config" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)

      copilot_user.dotcom_chat_enabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.dotcom_chat_enabled?
    end
  end

  context "mobile chat" do
    test "is disabled if any business is disabled" do
      user = create(:user)
      biz1 = create(:business)
      biz2 = create(:business)
      org1 = create(:business_organization, business: biz1)
      org2 = create(:business_organization, business: biz2)
      org1.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).enable_mobile_chat!
      Copilot::Business.new(biz2).disable_mobile_chat!
      user.reload

      assert Copilot::User.new(user).mobile_chat_disabled?
    end

    test "is enabled if all businesses are enabled" do
      user = create(:user)
      biz1 = create(:business)
      biz2 = create(:business)
      org1 = create(:business_organization, business: biz1)
      org2 = create(:business_organization, business: biz2)
      org1.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).enable_mobile_chat!
      Copilot::Business.new(biz2).enable_mobile_chat!
      user.reload

      public_user = Copilot::Public::User.new(user)
      assert public_user.mobile_chat_enabled?
    end

    test "is enabled if all orgs are enabled" do
      user = create(:user)
      biz = create(:business)
      org = create(:business_organization, business: biz)
      org2 = create(:organization)
      org.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      refute Copilot::User.new(user).mobile_chat_enabled?

      Copilot::Business.new(biz).mobile_chat_no_policy!
      Copilot::Organization.new(org).enable_mobile_chat!

      Copilot::Organization.new(org2).enable_mobile_chat!
      user.reload

      public_user = Copilot::Public::User.new(user)
      assert public_user.mobile_chat_enabled?
    end

    test "is disabled if any org is disabled" do
      user = create(:user)
      org = create(:organization)
      org2 = create(:organization)
      org.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org).enable_mobile_chat!
      Copilot::Organization.new(org2).disable_mobile_chat!
      user.reload

      public_user = Copilot::Public::User.new(user)
      refute public_user.mobile_chat_enabled?
    end

    test "not enabled for user, org or biz" do
      user = create(:user)
      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)

      public_user = Copilot::Public::User.new(user)
      refute public_user.mobile_chat_enabled?
    end

    test "is always enabled for CFI" do
      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.mobile_chat_enabled?
    end
  end

  context "Bing in dotcom chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_enable!

      public_user = Copilot::Public::User.new(user)
      assert public_user.bing_github_chat_enabled?
    end

    test "is disabled if part of multiple enterprises and one disables it" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_disabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!
      user.reload

      public_user = Copilot::Public::User.new(user)
      refute public_user.bing_github_chat_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_enable!
      Copilot::Organization.new(other_org).bing_github_chat_enable!

      public_user = Copilot::Public::User.new(user)
      assert public_user.bing_github_chat_enabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!

      public_user = Copilot::Public::User.new(user)
      refute public_user.bing_github_chat_enabled?
    end

    test "is disabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_enable!
      Copilot::Organization.new(other_org).bing_github_chat_disable!

      public_user = Copilot::Public::User.new(user)
      refute public_user.bing_github_chat_enabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_disable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!

      public_user = Copilot::Public::User.new(user)
      refute public_user.bing_github_chat_enabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_disable!
      Copilot::Organization.new(other_org).bing_github_chat_disable!

      public_user = Copilot::Public::User.new(user)
      refute public_user.bing_github_chat_enabled?
    end
  end

  context "a_chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_enabled!
      Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

      public_user = Copilot::Public::User.new(user)
      assert public_user.a_chat_enabled?
      refute public_user.a_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one disables it" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_disabled!
      user.reload

      public_user = Copilot::Public::User.new(user)
      refute public_user.a_chat_enabled?
      assert public_user.a_chat_disabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).a_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_enabled!
      Copilot::Organization.new(other_org).a_chat_enabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.a_chat_enabled?
      refute public_user.a_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.a_chat_enabled?
      assert public_user.a_chat_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_enabled!
      Copilot::Organization.new(other_org).a_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.a_chat_enabled?
      refute public_user.a_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_disabled!
      Copilot::Business.new(other_biz).a_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.a_chat_enabled?
      assert public_user.a_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).a_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_disabled!
      Copilot::Organization.new(other_org).a_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.a_chat_enabled?
      assert public_user.a_chat_disabled?
    end
  end

  context "o1" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_enabled!
      Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

      public_user = Copilot::Public::User.new(user)
      assert public_user.o1_enabled?
      refute public_user.o1_disabled?
    end

    test "is disabled if part of multiple enterprises and one disables it" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_disabled!
      user.reload

      public_user = Copilot::Public::User.new(user)
      refute public_user.o1_enabled?
      assert public_user.o1_disabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).o1_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_enabled!
      Copilot::Organization.new(other_org).o1_enabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.o1_enabled?
      refute public_user.o1_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.o1_enabled?
      assert public_user.o1_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_enabled!
      Copilot::Organization.new(other_org).o1_disabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.o1_enabled?
      refute public_user.o1_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_disabled!
      Copilot::Business.new(other_biz).o1_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.o1_enabled?
      assert public_user.o1_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).o1_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_disabled!
      Copilot::Organization.new(other_org).o1_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.o1_enabled?
      assert public_user.o1_disabled?
    end

    test "is always enabled for CFI" do
      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.o1_enabled?
      refute public_user.o1_disabled?
    end
  end

  context "g_chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_enabled!
      Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

      public_user = Copilot::Public::User.new(user)
      assert public_user.g_chat_enabled?
      refute public_user.g_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one disables it" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_disabled!
      user.reload

      public_user = Copilot::Public::User.new(user)
      refute public_user.g_chat_enabled?
      assert public_user.g_chat_disabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).g_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_enabled!
      Copilot::Organization.new(other_org).g_chat_enabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.g_chat_enabled?
      refute public_user.g_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.g_chat_enabled?
      assert public_user.g_chat_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_enabled!
      Copilot::Organization.new(other_org).g_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.g_chat_enabled?
      refute public_user.g_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_disabled!
      Copilot::Business.new(other_biz).g_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.g_chat_enabled?
      assert public_user.g_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).g_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_disabled!
      Copilot::Organization.new(other_org).g_chat_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.g_chat_enabled?
      assert public_user.g_chat_disabled?
    end

    test "is enabled for CFI when turning on" do
      Copilot::User.new(@cfi_user).g_chat_enabled!
      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.g_chat_enabled?
      refute public_user.g_chat_disabled?
    end

    test "is not configured by default" do
      public_user = Copilot::Public::User.new(@cfi_user)
      refute public_user.g_chat_enabled?
      refute public_user.g_chat_disabled?
    end

    test "is disabled for CFI when turning off" do
      Copilot::User.new(@cfi_user).g_chat_disabled!
      public_user = Copilot::Public::User.new(@cfi_user)
      refute public_user.g_chat_enabled?
      assert public_user.g_chat_disabled?
    end
  end

  context "#pr_summarizations_enabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).pr_summarizations_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        refute public_user.pr_summarizations_enabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).pr_summarizations_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        assert public_user.pr_summarizations_enabled?
      end
    end
  end

  context "#private_docs_enabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).private_docs_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_private_docs_enabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        refute public_user.private_docs_enabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).private_docs_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_private_docs_disabled, configurable: user)

        public_user = Copilot::Public::User.new(user)
        assert public_user.private_docs_enabled?
      end
    end
  end

  context "#extensions_enabled?" do
    test "true if the copilot_extensibility_policy_override flag is enabled for the user" do
      GitHub.flipper[:copilot_extensibility_policy_override].enable(@cfi_user)

      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.extensions_enabled?
    end

    test "false if at least one business disables it" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.extensions_enabled?
    end

    test "true if at least one business enables it and no others disable it" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_no_policy!

      public_user = Copilot::Public::User.new(user)
      assert public_user.extensions_enabled?
    end

    test "true if not controlled by a business and at least one organization enables it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_enabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      public_user = Copilot::Public::User.new(user)
      assert public_user.extensions_enabled?
    end

    test "false if not controlled by a business and all organizations disable it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_disabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      public_user = Copilot::Public::User.new(user)
      refute public_user.extensions_enabled?
    end

    test "true for cfi users in the copilot_extension_access flag" do
      GitHub.flipper[:copilot_extension_access].enable(@cfi_user)
      public_user = Copilot::Public::User.new(@cfi_user)
      assert public_user.extensions_enabled?
    end

    test "false for cfi users not in the copilot_extension_access flag" do
      GitHub.flipper[:copilot_extension_access].disable(@cfi_user)
      public_user = Copilot::Public::User.new(@cfi_user)
      refute public_user.extensions_enabled?
    end

    test "false by default" do
      user = create(:user)

      public_user = Copilot::Public::User.new(user)
      refute public_user.extensions_enabled?
    end
  end
end if GitHub.copilot_enabled?
