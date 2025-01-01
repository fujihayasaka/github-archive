# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationEnterpriseDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @admin = create(:user, login: "admin-one")
    @admin_two = create(:user, login: "admin-two")
    @admin_three = create(:user, login: "admin-three")
    @org = create :organization
    @org2 = create :organization

    @business = create :business, owners: [@admin, @admin_two, @admin_three], organizations: [@org, @org2]
    @business_billing_manager = create :user
    @business.billing.add_manager @business_billing_manager, actor: @admin

    @business_plus_org = create(:business_plus_organization, admin: @owner, billing_type: "invoice")
    @business_plus_card_org = create(:business_plus_organization, admin: @owner, billing_type: "card")
    @business_plus_card_org.terms_of_service.update(type: "Corporate", actor: @admin)
    @plan_subscription = create(:billing_plan_subscription, :zuora, user: @business_plus_card_org)

    @org_member = create :user
    @org.add_member @org_member

    @org2_member = create :user
    @org2.add_member @org2_member

    @shared_member = create :user
    @org.add_member @shared_member
    @org2.add_member @shared_member

    @org_repo = create(:private_repository, :minimal, owner: @org)
    @org_repo_collab = create :user
    @org_repo.add_member @org_repo_collab

    @org2_repo = create(:private_repository, :minimal, owner: @org2)
    @org2_repo_collab = create :user
    @org2_repo.add_member @org2_repo_collab

    @shared_repo_collab = create :user
    @org_repo.add_member @shared_repo_collab
    @org2_repo.add_member @shared_repo_collab

    unless GitHub.single_business_environment?
      org_for_trial = create :organization, admins: [@admin]
    end
  end

  setup do
    GitHub.flipper[:opt_out_org_to_EA_upgrade].disable
    @upgrade_params = ActionController::Parameters.new(
      business: {
        name: "I am a special enterprise",
        slug: "i-am-a-special-enterprise"
      }
    )
  end

  def people_query(query, role, organization, current_user)
    Organization::People::Query.new(
      query: "role:#{role} #{query}",
      organization: organization,
      current_user: current_user,
      role: role)
  end

  context "#unique_business_member_ids" do
    if GitHub.single_business_environment?
      test "returns an empty array" do
        assert_empty @org.unique_business_member_ids
      end
    else
      test "returns empty array for an org not part of a business" do
        non_business_org = create :organization
        assert_empty non_business_org.unique_business_member_ids
      end

      test "returns unique seated members of an organization in a business" do
        # verify that business admins, business billing managers,
        # org2 members and org2 repo collabs are not included in the results
        expected_users = [*@org.admins, @org_member, @org_repo_collab]
        assert_same_elements expected_users.map(&:id), @org.unique_business_member_ids
      end
    end
  end

  context "#transferable_settings" do
    test "empty when none of the available settings are set on the org" do
      assert_empty @org.transferable_settings
    end

    test "includes 2FA requirement when set on the org" do
      admin = create :two_factor_credential_user
      org = create :business_plus_organization, admin: admin
      org.enable_two_factor_required actor: admin
      assert org.transferable_settings.find { |s| s[:name] == :two_factor_authentication }
    end

    test "includes IP allow list when set on the org" do
      admin = create :user
      org = create :business_plus_organization, admin: admin
      create :ip_allowlist_entry, owner: org
      assert org.transferable_settings.find { |s| s[:name] == :ip_allow_list }
    end

    test "includes SSH CAs when set on the org" do
      admin = create :user
      org = create :business_plus_organization, admin: admin
      create :ssh_certificate_authority, owner: org
      assert org.transferable_settings.find { |s| s[:name] == :ssh_certificate_authorities }
    end

    test "includes domains when set on the org" do
      admin = create :user
      org = create :business_plus_organization, admin: admin
      create :verifiable_domain, owner: org
      assert org.transferable_settings.find { |s| s[:name] == :domains }
    end
  end

  context "#enterprise_owners" do
    test "returns all enterprise owners for an enterprise-owned organization" do
      result = @org.async_enterprise_owners.sync
      assert_same_elements [@admin, @admin_two, @admin_three], result.to_a
    end

    test "returns all enterprise owners, and properly excludes billing managers" do
      billing_manager = create :user
      @business.billing.add_manager billing_manager, actor: @admin

      result = @org.async_enterprise_owners.sync
      assert_same_elements [@admin, @admin_two, @admin_three], result.to_a
    end

    test "returns no enterprise owners if the organization is not enterprise-owned" do
      new_org = create :organization

      result = new_org.async_enterprise_owners.sync
      assert_same_elements [], result.to_a
    end

    test "returns all enterprise owners matching query" do
      result = @org.async_enterprise_owners(query: "t").sync
      assert_same_elements [@admin_two, @admin_three], result.to_a
    end

    test "returns all enterprise owners, ordered by login descending" do
      result = @org.async_enterprise_owners(order_by: { field: "LOGIN", direction: "DESC" }).sync
      assert_same_elements [@admin_two, @admin_three, @admin], result.to_a
    end

    test "returns all enterprise owners matching query, ordered by ascending login" do
      result = @org.async_enterprise_owners(query: "t", order_by: { field: "LOGIN", direction: "ASC" }).sync
      assert_same_elements [@admin_three, @admin_two], result.to_a
    end
  end

  context "#unaffiliated_enterprise_owners" do
    test "returns all unaffiliated enterprise owners for an enterprise-owned organization" do
      result = @org.async_unaffiliated_enterprise_owners.sync
      assert_same_elements [@admin, @admin_two, @admin_three], result.to_a
    end

    test "returns no enterprise owners if the organization is not enterprise-owned" do
      new_org = create :organization

      result = new_org.async_unaffiliated_enterprise_owners.sync
      assert_same_elements [], result.to_a
    end

    test "returns all unaffiliated enterprise owners matching query" do
      @org.add_member @admin_two

      result = @org.async_unaffiliated_enterprise_owners(query: "t").sync
      assert_same_elements [@admin_three], result.to_a
    end

    test "returns all unaffiliated enterprise owners, ordered by login descending" do
      @org.add_admin @admin_three

      result = @org.async_unaffiliated_enterprise_owners(order_by: { field: "LOGIN", direction: "DESC" }).sync
      assert_same_elements [@admin_two, @admin], result.to_a
    end

    test "returns all unaffiliated enterprise owners matching query, ordered by ascending login" do
      @org.add_admin @admin

      result = @org.async_unaffiliated_enterprise_owners(query: "t", order_by: { field: "LOGIN", direction: "DESC" }).sync
      assert_same_elements [@admin_three, @admin_two], result.to_a
    end
  end

  context "#affiliated_enterprise_owners" do
    test "returns no enterprise owners if the organization is not enterprise-owned" do
      new_org = create :organization

      result = new_org.async_affiliated_enterprise_owners
      assert_same_elements [], result.to_a
    end

    test "returns all enterprise owners, with organizational role owner, matching query" do
      @org.add_admin @admin_two
      @org.add_admin @admin_three

      result = @org.async_affiliated_enterprise_owners(people_query: people_query("two", "owner", @org, @admin_two)).sync
      assert_same_elements [@admin_two], result.to_a
    end

    test "returns all enterprise owners, with organizational role direct_member, ordered by login descending" do
      @org.add_member @admin_two
      @org.add_member @admin_three

      result = @org.async_affiliated_enterprise_owners(people_query: people_query("admin", "member", @org, @admin_two),
                                                       order_by: { field: "LOGIN", direction: "DESC" }).sync
      assert_same_elements [@admin_three, @admin_two], result.to_a
    end

    test "returns all enterprise owners matching query, with organizational role owner, ordered by ascending login" do
      @org.add_admin @admin_two
      @org.add_admin @admin_three

      result = @org.async_affiliated_enterprise_owners(people_query: people_query("admin", "owner", @org, @admin_two),
                                                       order_by: { field: "LOGIN", direction: "DESC" }).sync
      assert_same_elements [@admin_three, @admin_two], result.to_a
    end
  end

  unless GitHub.single_business_environment?
    context "#upgrade_to_enterprise_in_progress?" do
      test "true when upgrade is in progress" do
        org = create :organization, admins: [@admin], plan: "business"
        assert org.eligible_for_purchase_upgrade_to_enterprise?(actor: @admin)
        refute org.reload.upgrade_to_enterprise_in_progress?
        org.upgrade_to_enterprise_in_progress!(@business)
        assert org.reload.upgrade_to_enterprise_in_progress?
        assert_equal @business.id, org.reload.upgrade_to_enterprise_in_progress.id
        refute org.eligible_for_purchase_upgrade_to_enterprise?(actor: @admin)
        assert org.eligible_for_purchase_upgrade_to_enterprise?(actor: @admin, skip_in_progress_check: true)
        org.clear_upgrade_to_enterprise_in_progress!
        assert org.reload.eligible_for_purchase_upgrade_to_enterprise?(actor: @admin)
        refute org.upgrade_to_enterprise_in_progress?
      end
    end

    context "#eligible_for_upgrade_to_enterprise?" do
      if GitHub.single_business_environment?
        test "returns false when organization in a single business environment" do
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "invoice"

          refute org.business.present?
          assert org.plan.business_plus?
          assert org.invoiced?

          refute org.eligible_for_upgrade_to_enterprise?
        end
      else
        test "returns true for an organization that is eligible" do
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "invoice"

          refute org.business.present?
          assert org.plan.business_plus?
          assert org.invoiced?

          assert org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if organization has been opted out" do
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "invoice"
          GitHub.flipper[:opt_out_org_to_EA_upgrade].enable(org)

          refute org.business.present?
          assert org.plan.business_plus?
          assert org.invoiced?

          refute org.reload.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if organization is already tied to a business" do
          random_business = create :business, :with_self_serve_payment, owners: [@admin]
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "invoice", business: random_business

          assert org.business.present?
          assert org.plan.business_plus?
          assert org.invoiced?

          refute org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if organization is associated with a soft-deleted business" do
          random_business = create :business, :with_self_serve_payment, owners: [@admin]
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "invoice", business: random_business
          random_business.touch :deleted_at # Avoid using Business#soft_delete! which requires that all orgs be removed
          org.reload

          assert org.business_membership.present?
          assert org.plan.business_plus?
          assert org.invoiced?

          refute org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if the organization is not on the enterprise-plan" do
          org = create :organization, plan: "business", admins: [@admin], billing_type: "invoice"

          refute org.business.present?
          refute org.plan.business_plus?
          assert org.invoiced?

          refute org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false when feature flag enabled and organization does not have at least one owner" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          User.delete(org.admins)
          org.reload

          refute_predicate org.admins, :any?
          refute_predicate org, :eligible_for_upgrade_to_enterprise?
        end

        test "returns true if the organization is on card billing" do
          refute @business_plus_card_org.business.present?
          assert @business_plus_card_org.plan.business_plus?
          refute @business_plus_card_org.invoiced?

          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true if the organization is on card billing, and has an active coupon" do
          coupon = create(:coupon, duration: 365)
          @business_plus_card_org.redeem_coupon(coupon)

          refute @business_plus_card_org.invoiced?
          assert @business_plus_card_org.has_an_active_coupon?

          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if the organization is sponsors invoiced" do
          staff = create :staff_admin_user
          invoiced_sponsor_org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription, plan: "business_plus", admins: [staff])

          refute invoiced_sponsor_org.reload.invoiced?
          assert invoiced_sponsor_org.sponsors_invoiced?

          refute invoiced_sponsor_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true if the organization is on card billing, and does not have any coupons or sponsorships" do
          refute @business_plus_card_org.invoiced?
          refute @business_plus_card_org.has_an_active_coupon?
          refute @business_plus_card_org.sponsorships_as_sponsor.active.recurring.any?

          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true even if the organization has active marketplace listing subscription items" do
          Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])

          assert @business_plus_card_org.active_marketplace_listing_subscription_items.any?

          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if the organization is in dunning" do
          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise? # The upgrade should be allowed before the org is dunned

          @business_plus_card_org.increment_billing_attempts

          assert @business_plus_card_org.dunning?

          refute @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false if the organization does not have a valid Zuora subscription and no active coupon" do
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "card"
          plan_subscription = create(:billing_plan_subscription, user: org) # No Zuora

          refute org.plan_subscription.has_external_subscription?
          refute org.has_an_active_coupon?

          refute org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true if the organization has a valid Zuora subscription and no active coupon" do
          assert @business_plus_card_org.plan_subscription.has_external_subscription?
          refute @business_plus_card_org.has_an_active_coupon?

          assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true if the organization does not have a valid Zuora subscription but has an active coupon" do
          org = create :organization, plan: "business_plus", admins: [@admin], billing_type: "card"
          plan_subscription = create(:billing_plan_subscription, user: org) # No Zuora
          coupon = create(:coupon, duration: 365)
          org.redeem_coupon(coupon)

          refute org.plan_subscription.has_external_subscription?
          assert org.has_an_active_coupon?

          assert org.eligible_for_upgrade_to_enterprise?
        end

        test "returns true for an organization with a valid trade screening record" do
          org = create :organization, :with_account_screening_profile, plan: "business_plus", admins: [@admin], billing_type: "card"
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          assert org.trade_screening_record.valid?(:entity)
          assert_predicate org.trade_screening_record, :valid?

          assert org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false for an organization with a trade screening record in review" do
          org = create :organization, :with_account_screening_profile, plan: "business_plus", admins: [@admin], billing_type: "card"
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          org.trade_screening_record.hit_in_review!

          assert org.trade_screening_record.valid?(:entity)
          assert_predicate org.trade_screening_record, :valid?
          assert org.trade_screening_record.hit_in_review?

          refute org.eligible_for_upgrade_to_enterprise?
        end

        test "returns false for an organization with a true_match trade screening record" do
          org = create :organization, :with_account_screening_profile, plan: "business_plus", admins: [@admin], billing_type: "card"
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          org.trade_screening_record.update!(msft_trade_screening_status: "true_match")

          assert org.trade_screening_record.valid?(:entity)
          assert_predicate org.trade_screening_record, :valid?
          assert org.trade_screening_record.true_match?

          refute org.eligible_for_upgrade_to_enterprise?
        end
      end
    end

    context "#required_to_upgrade_to_enterprise" do
      test "returns true for a business_plus plan organization" do
        assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?

        assert @business_plus_card_org.required_to_upgrade_to_enterprise?
      end

      test "returns false if the organization is not eligible for upgrade to enterprise" do
        org = create :organization, plan: "business", billing_type: "card", admins: [@admin]
        refute org.eligible_for_upgrade_to_enterprise? # Not business_plus plan

        refute org.required_to_upgrade_to_enterprise?
      end

      test "returns false if the organization is on the invoice billing type" do
        org = create :organization, plan: "business_plus", billing_type: "invoice", admins: [@admin]
        assert org.eligible_for_upgrade_to_enterprise?

        refute org.required_to_upgrade_to_enterprise?
      end

      test "returns false if the organization has SAML SSO enabled" do
        provider = create(:organization_saml_provider)
        org = provider.organization
        org.plan = GitHub::Plan.business_plus
        plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
        assert org.eligible_for_upgrade_to_enterprise?

        refute org.required_to_upgrade_to_enterprise?
      end

      test "returns false if the organization is on the Standard terms of service" do
        @business_plus_card_org.terms_of_service.update(type: "Standard", actor: @admin)
        assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?

        refute @business_plus_card_org.required_to_upgrade_to_enterprise?
      end

      test "returns false if the organization has an active coupon part of the emu_opensource program" do
        @business_plus_card_org.redeem_coupon create(:coupon, discount: 0.25, code: "emu-opensource")
        assert @business_plus_card_org.eligible_for_upgrade_to_enterprise?

        refute @business_plus_card_org.required_to_upgrade_to_enterprise?
      end
    end

    context "#perform_direct_upgrade_to_enterprise" do
      test "successfully creates a business for admin with an invoiced billing org eligible for upgrading to enterprise" do
        assert_predicate @business_plus_org, :eligible_for_upgrade_to_enterprise?

        @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_org.reload

        refute_nil business = @business_plus_org.business
        assert_predicate business, :can_self_serve?
        assert_predicate business, :invoiced?
        assert_predicate business, :organization_direct_upgraded?  # Business is set to direct upgraded state
        assert_equal "I am a special enterprise", business.name
        assert_equal "i-am-a-special-enterprise", business.slug
        assert_same_elements @business_plus_org.admins, business.owners
        assert_equal @business_plus_org.billing_email, business.billing_email
        assert_equal @business_plus_org.seats, business.seats
        assert_equal @business_plus_org.billed_on, business.billed_on
      end

      test "successfully creates a business for admin with a card billing org eligible for upgrading to enterprise" do
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.business
        assert_predicate business, :can_self_serve?
        assert_predicate business, :self_serve_payment?
        assert_predicate business, :organization_direct_upgraded?  # Business is set to direct upgraded state
        assert_equal "I am a special enterprise", business.name
        assert_equal "i-am-a-special-enterprise", business.slug
        assert_same_elements @business_plus_card_org.admins, business.owners
        assert_equal @business_plus_card_org.billing_email, business.billing_email
        assert_equal @business_plus_card_org.seats, business.seats
        assert_equal @business_plus_card_org.billed_on, business.billed_on
      end

      test "creates a business on a monthly billing cadence when upgrading from a card billing org on monthly payments" do
        business_plus_card_org = create(:business_plus_organization, admin: @owner, billing_type: "card", plan_duration: User::BillingDependency::MONTHLY_PLAN)
        business_plus_card_org.customer = create :credit_card_customer
        plan_subscription = create(:billing_plan_subscription, :zuora, user: business_plus_card_org)
        assert_predicate business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_equal business_plus_card_org.plan_duration, "month"

        business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        business_plus_card_org.reload

        refute_nil business = business_plus_card_org.business
        assert_predicate business, :self_serve_payment?
        assert_equal "i-am-a-special-enterprise", business.slug
        assert_equal business.plan_duration, "month"
      end

      test "creates a business on a yearly billing cadence when upgrading from a card billing org on yearly payments" do
        @business_plus_card_org.update!(plan_duration: User::BillingDependency::YEARLY_PLAN)
        assert_equal @business_plus_card_org.plan_duration, "year"

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.business
        assert_predicate business, :self_serve_payment?
        assert_equal "i-am-a-special-enterprise", business.slug
        assert_equal business.plan_duration, "year"
      end

      test "enables auto-pay on the business if the upgrading self-serve org was on auto-pay" do
        @business_plus_card_org.customer = create :credit_card_customer
        assert_empty @business_plus_card_org.customer.auto_pay_reasons

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.business
        assert_empty business.customer.auto_pay_reasons
      end

      test "does not enable auto-pay on the business if the upgrading self-serve org was not on auto-pay" do
        @business_plus_card_org.customer = create :credit_card_customer
        @business_plus_card_org.disable_auto_pay!(:india_rbi)
        refute_empty @business_plus_card_org.customer.auto_pay_reasons

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.business
        refute_empty business.customer.auto_pay_reasons
      end

      test "does not enable auto-pay on a business upgraded from an invoiced org" do
        assert_nil @business_plus_org.reload.customer

        @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_org.reload

        refute_nil business = @business_plus_org.business
        assert_nil business.customer.auto_pay?
      end

      test "transfers active coupon from card billing org to card billing business, if present" do
        coupon = create(:coupon, plan: "business_plus")
        @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from card billing org to card billing business, even if org does not have a plan subscription" do
        coupon = create(:coupon, plan: "business_plus", discount: "100%")
        business_plus_card_org = create(:business_plus_organization, admin: @admin, billing_type: "card")
        business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate business_plus_card_org, :has_an_active_coupon?
        assert_nil business_plus_card_org.plan_subscription

        business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        business_plus_card_org.reload

        refute_nil business = business_plus_card_org.reload.business
        refute_predicate business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from org to business, even if coupon's limit is already 0" do
        coupon = create(:coupon, plan: "business_plus", limit: 1)
        @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_equal coupon.reload.limit, 0

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from org to business, even if coupon can only be applied by a staff user" do
        staff_user = create(:user, :staff)
        coupon = create(:coupon, plan: "business_plus", staff_actor_only: true)
        @business_plus_card_org.redeem_coupon(coupon.code, actor: staff_user)
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from org to business, even if coupon has expired since it was applied to the org" do
        coupon = create(:coupon, plan: "business_plus")
        @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?
        coupon.update!(expires_at: Time.current - 1.day)
        assert_predicate coupon.reload, :expired?

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from org to business, even if the org doesn't have an external subscription" do
        coupon = create(:coupon, plan: "business_plus")
        business_plus_card_org = create(:business_plus_organization, admin: @admin, billing_type: "card")
        plan_subscription = create(:billing_plan_subscription, user: business_plus_card_org) # no zuora
        business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_nil business_plus_card_org.plan_subscription.external_subscription
        assert_predicate business_plus_card_org, :has_an_active_coupon?

        business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        business_plus_card_org.reload

        refute_nil business = business_plus_card_org.reload.business
        refute_predicate business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
      end

      test "transfers active coupon from org to business, but only applies it for the remaining duration of the coupon" do
        coupon = create(:coupon, plan: "business_plus", duration: 31)
        travel_to 10.days.ago do
          @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        end

        org_coupon_redemption = @business_plus_card_org.coupon_redemption
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?

        @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_card_org.reload

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
        assert_equal org_coupon_redemption.expires_at, business.coupon_redemption.expires_at
      end

      test "upgrades successfully even if the org's filled seats is greater than its number of seats, because the org's coupon allows for unlimited seats" do
        coupon = create(:coupon, plan: "business_plus", discount: 1.0)
        business_plus_card_org = create(:business_plus_organization, admin: @admin, billing_type: "card", seats: 1)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: business_plus_card_org)
        business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)

        10.times { business_plus_card_org.add_member(create(:user)) }
        org_filled_seats = business_plus_card_org.filled_seats
        org_seats = business_plus_card_org.seats
        assert_equal org_filled_seats, org_seats + 10
        assert_predicate business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate business_plus_card_org, :has_an_active_coupon?
        assert_predicate business_plus_card_org, :has_unlimited_seats?

        business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        business_plus_card_org.reload

        refute_nil business = business_plus_card_org.reload.business
        refute_predicate business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?
        assert_equal business.seats, org_filled_seats
        refute_equal business.seats, org_seats
      end

      test "transfers active coupon from ghec org to business and informs customer of coupon transfer by email" do
        coupon = create(:coupon, plan: "business_plus")
        @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate @business_plus_card_org, :has_an_active_coupon?

        perform_enqueued_jobs(only: [ApplicationDeliveryJob, BusinessCreatedFromOrganizationJob]) do
          @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_card_org.reload
        end

        refute_nil business = @business_plus_card_org.reload.business
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        assert_predicate business, :has_an_active_coupon?

        mail = ActionMailer::Base.deliveries.last
        assert_equal \
          "[GitHub] #{business.name} enterprise created for the #{@business_plus_card_org.safe_profile_name} organization",
          mail.subject
        assert_includes \
          mail.html_part.body.to_s,
          "The #{@business_plus_card_org.safe_profile_name} organization's current coupon has been transferred to the #{business.name} enterprise. The conditions and remaining duration of the coupon will carry over."
        assert_includes mail.bcc, business.owners.first.email
      end

      test "instruments upgrade_from_organization audit log event when upgrade is successful" do
        events = assert_performed_audit_entries(count: 1, only: "business.upgrade_from_organization") do
          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload
        end

        @business_plus_org.reload
        business = @business_plus_org.business

        expected_payload = {
          business: business.slug,
          business_id: business.id,
          org: @business_plus_org.login,
          org_id: @business_plus_org.id
        }

        assert_subset_hash expected_payload, events.first
      end

      test "job to onboard organization to sponsors is enqueued after upgrade" do
        assert_enqueued_with(job: SponsorsBusinessOrgOnboardingJob, args: [organization: @business_plus_card_org, actor: @admin]) do
          @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_card_org.reload
        end
      end

      if GitHub.hydro_enabled?
        test "publishes github.enterprise_account.v0.OrganizationUpgrade when successful" do
          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload

          @business_plus_org.reload
          refute_nil business = @business_plus_org.business
          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_org),
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_previous_plan: "business_plus",
            organization_previous_customer_id: nil,
            billing_type: "invoice",
            status: :DIRECT_UPGRADED,
          }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
        end

        test "publishes coupon information to hydro if the upgrading org has an active coupon that is successfully transferred to the business" do
          coupon = create(:coupon, plan: "business_plus")
          @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
          assert_predicate @business_plus_card_org, :has_an_active_coupon?

          org_customer_id_before_upgrade = @business_plus_card_org.customer.id

          @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_card_org.reload

          refute_nil business = @business_plus_card_org.reload.business
          refute_predicate @business_plus_card_org, :has_an_active_coupon?
          assert_predicate business, :has_an_active_coupon?
          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_card_org),
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_previous_plan: "business_plus",
            organization_previous_customer_id: org_customer_id_before_upgrade,
            billing_type: "card",
            status: :DIRECT_UPGRADED,
            coupon_transfer_attempted: true,
            coupon_transfer_succeeded: true,
            coupon_code: coupon.code,
          }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
        end

        test "publishes coupon information to hydro if the upgrading org has an active coupon that is not successfully transferred to the business" do
          coupon = create(:coupon, plan: "business_plus")
          @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
          assert_predicate @business_plus_card_org, :has_an_active_coupon?
          Business.any_instance.stubs(:has_an_active_coupon?).returns(false)

          org_customer_id_before_upgrade = @business_plus_card_org.customer.id

          @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_card_org.reload

          refute_nil business = @business_plus_card_org.reload.business
          refute_predicate @business_plus_card_org, :has_an_active_coupon?
          refute_predicate business, :has_an_active_coupon?

          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_card_org),
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_previous_plan: "business_plus",
            organization_previous_customer_id: org_customer_id_before_upgrade,
            billing_type: "card",
            status: :DIRECT_UPGRADED,
            marketplace_subscription: false,
            coupon_transfer_attempted: true,
            coupon_transfer_succeeded: false,
            coupon_code: coupon.code,
          }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
        end

        test "publishes the customer id to hydro when the upgrading org was associated with a customer_account before upgrading" do
          @business_plus_org.customer = create :credit_card_customer

          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload

          @business_plus_org.reload
          refute_nil business = @business_plus_org.business
          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_org),
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_previous_plan: "business_plus",
            organization_previous_customer_id: @business_plus_org.customer.id,
            billing_type: "invoice",
            status: :DIRECT_UPGRADED,
          }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
        end

        test "publishes to hydro if the upgrade fails with a non-couponed GHEC org" do
          @business_plus_org.seats = 2
          @business_plus_org.save
          4.times { @business_plus_org.add_member create(:user) }
          assert @business_plus_org.reload.filled_seats > @business_plus_org.seats
          error_message = "Not enough seats to add the organization to the enterprise account. Please contact sales at https://enterprise.github.localhost/contact to add more seats before proceeding"

          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload

          @business_plus_org.reload
          assert_nil business = @business_plus_org.business
          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_org),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_plan: "business_plus",
            billing_type: "invoice",
            has_active_coupon: false,
            error_message: error_message,
            slug: "i-am-a-special-enterprise"
          }, schema: "github.enterprise_account.v0.OrganizationUpgradeFailure")
        end

        test "publishes to hydro if the upgrade fails with a couponed GHEC org" do
          coupon = create(:coupon, plan: "business_plus")
          @business_plus_card_org.redeem_coupon(coupon.code, actor: @admin)
          assert_predicate @business_plus_card_org, :has_an_active_coupon?

          @business_plus_card_org.seats = 2
          @business_plus_card_org.save
          4.times { @business_plus_card_org.add_member create(:user) }
          assert @business_plus_card_org.reload.filled_seats > @business_plus_card_org.seats
          error_message = "Not enough seats to add the organization to the enterprise account. Please contact sales at https://enterprise.github.localhost/contact to add more seats before proceeding"

          @business_plus_card_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_card_org.reload

          @business_plus_card_org.reload
          assert_nil business = @business_plus_card_org.business
          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            organization: Hydro::EntitySerializer.organization(@business_plus_card_org),
            actor: Hydro::EntitySerializer.user(@admin),
            organization_plan: "business_plus",
            billing_type: "card",
            has_active_coupon: true,
            coupon_code: coupon.code,
            error_message: error_message,
            slug: "i-am-a-special-enterprise"
          }, schema: "github.enterprise_account.v0.OrganizationUpgradeFailure")
        end
      end

      test "successfully sets the onboarding notice on all owners of the business when direct upgrade is successful" do
        assert_predicate @business_plus_org, :eligible_for_upgrade_to_enterprise?
        @business_plus_org.add_admin(create(:user))
        assert @business_plus_org.admins.count > 1

        @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
        @business_plus_org.reload

        business = @business_plus_org.reload.business
        refute_nil business
        assert_predicate business, :organization_direct_upgraded?
        assert_predicate business, :upgraded_from_organization?
        assert_same_elements business.owners, @business_plus_org.admins
        business.owners.each do |owner|
          assert business.org_upgrade_onboarding_notice_set?(owner)
        end
      end

      test "transfers configuration to enterprise when selected" do
        assert_predicate @business_plus_org, :eligible_for_upgrade_to_enterprise?
        create :verifiable_domain, owner: @business_plus_org
        create :verifiable_domain, owner: @business_plus_org, verified: true
        @business_plus_org.enable_notification_restrictions actor: @admin
        create :ip_allowlist_entry, owner: @business_plus_org, allow_list_value: "1.1.1.0/24"
        create :ip_allowlist_entry, owner: @business_plus_org
        @business_plus_org.enable_ip_allowlist actor: @admin

        perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
          @upgrade_params[:transfer_ip_allow_list] = "1"
          @upgrade_params[:transfer_domains] = "1"
          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload
        end

        assert business = @business_plus_org.reload.business
        assert_equal 2, business.ip_allowlist_entries.count
        assert_predicate business.reload, :ip_allowlist_enabled?
        assert_predicate @business_plus_org.reload, :ip_allowlist_enabled?
        assert_equal 2, business.verifiable_domains.count
        assert_predicate business.reload, :restrict_notifications_to_verified_domains?
        assert_predicate @business_plus_org.reload, :restrict_notifications_to_verified_domains?
      end

      test "does not transfer configuration to enterprise when not selected" do
        assert_predicate @business_plus_org, :eligible_for_upgrade_to_enterprise?
        create :verifiable_domain, owner: @business_plus_org
        create :verifiable_domain, owner: @business_plus_org, verified: true
        @business_plus_org.enable_notification_restrictions actor: @admin
        create :ip_allowlist_entry, owner: @business_plus_org, allow_list_value: "1.1.1.0/24"
        create :ip_allowlist_entry, owner: @business_plus_org
        @business_plus_org.enable_ip_allowlist actor: @admin

        perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
          @business_plus_org.perform_direct_upgrade_to_enterprise(@upgrade_params, @admin)
          @business_plus_org.reload
        end

        assert business = @business_plus_org.reload.business
        assert_equal 0, business.ip_allowlist_entries.count
        refute_predicate business.reload, :ip_allowlist_enabled?
        assert_predicate @business_plus_org.reload, :ip_allowlist_enabled?
        assert_equal 0, business.verifiable_domains.count
        refute_predicate business.reload, :restrict_notifications_to_verified_domains?
        assert_predicate @business_plus_org.reload, :restrict_notifications_to_verified_domains?
      end
    end

    context "#eligible_for_purchase_upgrade_to_enterprise" do
      test "returns true for an organization that is eligible" do
        org = create :organization, plan: "business", admins: [@admin]

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        assert org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns true for an organization with active marketplace listing subscription items" do
        Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
        org = create :organization, plan: "business", admins: [@admin]

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        assert org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns false if organization is already tied to a business" do
        random_business = create :business, :with_self_serve_payment, owners: [@admin]
        org = create :organization, plan: "business", admins: [@admin], business: random_business

        assert org.business.present?
        refute org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns false if organization is associated with a soft-deleted business" do
        random_business = create :business, :with_self_serve_payment, owners: [@admin]
        org = create :organization, plan: "business", admins: [@admin], business: random_business
        random_business.touch :deleted_at # Avoid using Business#soft_delete! which requires that all orgs be removed
        org.reload

        assert org.business_membership.present?
        refute org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns false if the organization is on the enterprise-plan" do
        org = create :organization, plan: "business_plus", admins: [@admin]

        refute org.business.present?
        assert org.plan.business_plus?
        refute org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns false if the organization is on invoiced billing" do
        org = create :organization, plan: "business", admins: [@admin]
        org.update!(billing_type: "invoice")

        refute org.business.present?
        refute org.plan.business_plus?
        assert org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.eligible_for_purchase_upgrade_to_enterprise?
      end

      test "returns false if the organization has already initiated an upgrade to enterprise" do
        org = create :organization, plan: "business", admins: [@admin]
        upgraded_business = create :business, owners: [@admin]
        org.upgrade_to_enterprise_in_progress!(upgraded_business)

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.active_marketplace_listing_subscription_items.any?
        assert org.upgrade_to_enterprise_in_progress?

        refute org.eligible_for_purchase_upgrade_to_enterprise?
      end
    end

    context "#selectable_for_enterprise_trial?" do
      test "returns true for an org that is selectable" do
        org = create :organization, admins: [@admin]
        trial_business = create(:business, owners: [@admin])

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        assert org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if org is already tied to a business" do
        random_business = create :business, :with_self_serve_payment, owners: [@admin], downgraded_at: GitHub::Billing.now
        org = create :organization, admins: [@admin], business: random_business
        trial_business = create(:business, owners: [@admin])

        assert org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if org is associated with a soft-deleted business" do
        random_business = create :business, :with_self_serve_payment, owners: [@admin], downgraded_at: GitHub::Billing.now
        org = create :organization, admins: [@admin], business: random_business
        random_business.touch :deleted_at # Avoid using Business#soft_delete! which requires that all orgs be removed
        trial_business = create(:business, owners: [@admin])
        org.reload

        assert org.business_membership.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if an org is already on the enterprise plan" do
        org = create(:organization, admin: @admin, plan: "business_plus")
        trial_business = create(:business, owners: [@admin])

        refute org.business.present?
        assert org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if the org is invoiced" do
        org = create :organization, admins: [@admin], plan: "business", billing_type: "invoice"
        trial_business = create(:business, owners: [@admin])

        refute org.business.present?
        refute org.plan.business_plus?
        assert org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if the org has too many seats" do
        trial_business = create(:business, owners: [@admin])
        trial_business.update!(seats: trial_business.consumed_invitable_licenses)
        org = create(:organization) # 1 new admin

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if org has marketplace subscriptions" do
        Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
        org = create :organization, admins: [@admin]
        trial_business = create(:business, owners: [@admin])

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        assert org.active_marketplace_listing_subscription_items.any?
        refute org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end

      test "returns false if org has initiated an upgrade to enterprise" do
        org = create :organization, admins: [@admin]
        trial_business = create(:business, owners: [@admin])
        upgraded_business = create :business, owners: [@admin]
        org.upgrade_to_enterprise_in_progress!(upgraded_business)

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert trial_business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        assert org.upgrade_to_enterprise_in_progress?

        refute org.selectable_for_enterprise_trial?(trial_business)
      end
    end

    context "#selectable_for_business_created_from_coupon?" do
      test "returns true for a selectable organization" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        org = create :organization, admin: @admin, billing_type: "card"
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.dunning?

        assert org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if the feature flag is disabled" do
        GitHub.flipper[:new_ea_creation_from_coupon].disable
        org = create :organization, admin: @admin, billing_type: "card"
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if org is already tied to a business" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        prior_business = create :business, :with_self_serve_payment
        org = create(:organization, admin: @admin, business: prior_business)
        business = create :business, owners: [@admin], seats: org.default_seats

        assert org.business.present?
        assert org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if an org is already on the enterprise plan" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        org = create(:organization, admin: @admin, plan: "business_plus")
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        assert org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if org is already in upgrade_to_enterprise_in_progress? state" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        org = create :organization, admins: [@admin], plan: "business"
        prior_business = create :business
        org.upgrade_to_enterprise_in_progress!(prior_business)
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        assert org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        refute org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if org is invoiced" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        org = create :organization, admins: [@admin], plan: "business", billing_type: "invoice"
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        refute org.plan.business_plus?
        assert org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns true even if the org has active marketplace subscriptions" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
        org = create :organization, admin: @admin, billing_type: "card"
        business = create :business, owners: [@admin], seats: org.default_seats

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        assert org.active_marketplace_listing_subscription_items.any?
        refute org.dunning?

        assert org.selectable_for_business_created_from_coupon?(@admin)
      end

      test "returns false if the org is in dunning" do
        GitHub.flipper[:new_ea_creation_from_coupon].enable
        org = create :organization, admin: @admin, billing_type: "card"
        business = create :business, owners: [@admin], seats: org.default_seats
        org.increment_billing_attempts

        refute org.business.present?
        refute org.plan.business_plus?
        refute org.invoiced?
        refute org.upgrade_to_enterprise_in_progress?
        assert business.has_sufficient_licenses_for_organization?(org)
        refute org.active_marketplace_listing_subscription_items.any?
        assert org.dunning?

        refute org.selectable_for_business_created_from_coupon?(@admin)
      end
    end

    context "#owned_by_metered_plan_business?" do
      test "returns false for standalone org" do
        org = create :organization
        assert_nil org.business

        refute_predicate org, :owned_by_metered_plan_business?
      end

      test "returns false for org owned by business not on a metered billing plan" do
        refute_nil @org.business
        refute_predicate @org.business, :metered_plan?

        refute_predicate @org, :owned_by_metered_plan_business?
      end

      test "returns true for org owned by business on a metered billing plan" do
        @org.business.customer.update metered_ghe: true
        refute_nil @org.business
        assert_predicate @org.business.reload, :metered_plan?

        assert_predicate @org, :owned_by_metered_plan_business?
      end
    end

    context "#owned_by_metered_plan_trial_business?" do
      test "returns false for standalone org" do
        org = create :organization
        assert_nil org.business

        refute_predicate org, :owned_by_metered_plan_trial_business?
      end

      test "returns false for org owned by business not on a metered billing plan" do
        refute_nil @org.business
        refute_predicate @org.business, :metered_plan?

        refute_predicate @org, :owned_by_metered_plan_trial_business?
      end

      test "returns false for org owned by business on a metered billing plan and not in trial" do
        @org.business.customer.update metered_ghe: true
        refute_nil @org.business
        assert_predicate @org.business.reload, :metered_plan?
        refute_predicate @org.business, :trial?

        refute_predicate @org, :owned_by_metered_plan_trial_business?
      end

      test "returns true for org owned by business on a metered billing plan and in trial" do
        @org.business.customer.update metered_ghe: true
        @org.business.update trial_expires_at: 1.month.from_now
        refute_nil @org.business
        assert_predicate @org.business.reload, :metered_plan?
        assert_predicate @org.business, :trial?

        assert_predicate @org, :owned_by_metered_plan_trial_business?
      end
    end
  end
end
