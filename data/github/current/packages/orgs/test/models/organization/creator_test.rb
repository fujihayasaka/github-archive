# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCreatorTest < GitHub::TestCase
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper
  include AuditLogHelpers
  include HydroTestHelpers

  fixtures do
    @user      = create(:user, login: "org-admin")
    @org_attrs = {
      login: "new-org",
      admin_logins: [@user.login],
      billing_email: "admin@github.com",
      seats: 20,
    }
    @business = create :business, owners: [@user]
  end

  setup do
    setup_currency_exchange
  end

  test "fails if current_user is nil" do
    result = Organization::Creator.perform(nil, GitHub::Plan.free, @org_attrs)
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
    assert_predicate result.error_message, :present?
  end

  test "fails if org is business owned and no company name" do
    result = Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs, business_owned: true)
    refute result.success?
    refute result.organization.persisted?
    assert result.error_message.present?
  end

  test "fails if current_user has unverified email", skip_enterprise: true do
    unverified_user = create(:user)
    assert unverified_user.should_verify_email?
    result = Organization::Creator.perform(unverified_user, GitHub::Plan.free, @org_attrs)
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
    assert_predicate result.error_message, :present?
  end

  test "fails if current_user has hit_in_review screening status", skip_enterprise: true do
    profile = create(:account_screening_profile)
    user = profile.user
    user.enable_feature(:live_sdn_screening)

    profile.hit_in_review!

    result = Organization::Creator.perform(user, GitHub::Plan.free, @org_attrs)
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
    assert_predicate result.error_message, :present?
    assert_equal result.error_message, TradeControls::Notices.trade_screening_customer_account_under_review_for_less_than_2_days
  end

  test "succeeds if current_user with lic_r screening status is creating a free org", skip_enterprise: true do
    user = create(:user, :verified)
    profile = create(:account_screening_profile, owner: user, msft_trade_screening_status: :lic_r, last_trade_screen_date: 8.days.ago)

    user.enable_feature(:live_sdn_screening)

    result = Organization::Creator.perform(user, GitHub::Plan.free, @org_attrs)
    assert_predicate result, :success?
    assert_predicate result.organization, :persisted?
    refute_predicate result.error_message, :present?
    assert_empty result.error_message
  end

  test "fails if current_user with lic_r screening status is creating a paid org", skip_enterprise: true do
    user = create(:user, :verified)
    profile = create(:account_screening_profile, owner: user, msft_trade_screening_status: :lic_r, last_trade_screen_date: 8.days.ago)

    user.enable_feature(:live_sdn_screening)

    result = Organization::Creator.perform(user, GitHub::Plan.business_plus, @org_attrs.merge(seats: 5))
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
    assert_predicate result.error_message, :present?
    assert_equal result.error_message, TradeControls::Notices.trade_screening_customer_account_permanently_blocked_after_review
  end

  test "fails if current_user has a permanently blocked screening status", skip_enterprise: true do
    profile = create(:account_screening_profile, msft_trade_screening_status: :ssi_d, last_trade_screen_date: 8.days.ago)

    user = profile.user

    user.enable_feature(:live_sdn_screening)

    result = Organization::Creator.perform(user, GitHub::Plan.free, @org_attrs)
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
    assert_predicate result.error_message, :present?
    assert_equal result.error_message, TradeControls::Notices.trade_screening_customer_account_permanently_blocked_after_review
  end

  test "logs failure to splunk when organization is rolled back", skip_enterprise: true do
    GitHub.flipper[:live_sdn_screening].enable

    screening_info_keys = AccountScreeningProfile::PII_DATA_FIELDS + %w[vat_code entity_name]
    profile = build(:account_screening_profile, :with_org)
    screening_info = profile.attributes.slice(*screening_info_keys)

    TradeCompliance::TradeScreening::ApiService.stubs(:live_connection).raises(Faraday::Error)

    logger_calls = {}
    GitHub.logger.expects(:error).at_least_once.with do |exception, tags|
      logger_calls[exception] = tags
      true
    end

    result = Organization::Creator.perform(@user, GitHub::Plan.business_plus, @org_attrs.merge(seats: 5), trade_screening_info: screening_info)

    assert logger_calls.has_key?("organization_creation.failed"), "Expected organization_creation.failed event"
    external_uuid = logger_calls["organization_creation.failed"][:"gh.organization_creation.external_uuid"]
    assert_predicate external_uuid, :present?, "Expected external_uuid to be present"
    refute_predicate AccountScreeningProfile.find_by(external_uuid: external_uuid), :present?
    refute_predicate result, :success?
    refute_predicate result.organization, :persisted?
  end

  test "sets TOS if org is business owned to corporate" do
    org_hash = { company_name: "New Org" }.merge!(@org_attrs)
    Organization::Creator.perform(@user, GitHub::Plan.free, org_hash, business_owned: true, terms_of_service: "corporate")
    org = Organization.find_by_login("new-org")

    assert_predicate org.terms_of_service, :corporate?
  end

  test "logs company_name to an orgs.update_terms_of_service event when CToS is accepted" do
    events = subscribe "org.update_terms_of_service"

    result = Organization::Creator.perform(
      @user,
      GitHub::Plan.free,
      { company_name: "Megacorp" }.merge!(@org_attrs),
      business_owned: true,
      terms_of_service: "corporate"
    )

    assert_predicate result, :success?

    assert event = events.pop, "an org.update_terms_of_service event was expected"
    assert_equal "Megacorp", event.payload[:company_name][:new_value]
    assert_equal "Corporate", event.payload[:terms_of_service_type][:new_value]

    assert_equal "Megacorp", Organization.find_by_login("new-org").company.name
  end

  test "sets TOS if org is business owned to evaluation" do
    org_hash = { company_name: "New Org" }.merge!(@org_attrs)
    Organization::Creator.perform(@user, GitHub::Plan.free, org_hash, business_owned: true, terms_of_service: "evaluation")
    org = Organization.find_by_login("new-org")

    assert_predicate org.terms_of_service, :evaluation?
  end

  test "sets seats to zero if plan is free" do
    assert_nil Organization.find_by_login("new-org")

    Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
    org = Organization.find_by_login("new-org")

    assert_equal 0, org.seats
  end

  test "sets seats to zero if plan is not per_seat" do
    assert_nil Organization.find_by_login("new-org")

    Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
    org = Organization.find_by_login("new-org")

    assert_equal 0, org.seats
  end

  test "sets display_login" do
    assert_nil Organization.find_by_login("new-org")

    Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
    org = Organization.find_by_login("new-org")

    assert_equal User.to_display_login(org.login), org.read_attribute(:display_login)
  end

  test "enqueues an org creation job for free plans" do
    OrgCreationJob.expects(:perform_later).with do |user_id, org_id|
      user_id == @user.id &&
      org_id == Organization.find_by_login("new-org").id
    end

    perform_enqueued_jobs(only: [OrgCreationJob]) do
      Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
    end
  end

  test "enqueues an org creation job if billing succeeds" do
    OrgCreationJob.expects(:perform_later).with do |user_id, org_id|
      user_id == @user.id &&
      org_id == Organization.find_by_login("new-org").id
    end
    GitHub::Billing.expects(:signup).returns(stub(success?: true, error_message: "\o/"))

    perform_enqueued_jobs(only: [OrgCreationJob]) do
      Organization::Creator.perform(@user, GitHub::Plan.bronze, @org_attrs, payment_details: { present: true })
    end
  end

  test "does not emit hydro events for failed billing" do
    GitHub::Billing.expects(:signup).returns(stub(success?: false, error_message: "\o/"))
    Organization::Creator.perform(@user, GitHub::Plan.bronze, @org_attrs, payment_details: { present: true })

    refute_hydro_messages(schema: "github.v1.BillingPlanChange")
  end

  test "does not notify admins directly" do
    OrgCreationJob.expects(:perform_later).with do |user_id, org_id|
      user_id == @user.id &&
      org_id == Organization.find_by_login("new-org").id
    end
    OrganizationMailer.expects(:admin_added).never
    GitHub::Billing.expects(:signup).returns(stub(success?: true, error_message: "\o/"))

    perform_enqueued_jobs(only: [OrgCreationJob]) do
      Organization::Creator.perform(@user, GitHub::Plan.bronze, @org_attrs, payment_details: { present: true })
    end
  end

  test "does not enqueue an org creation job if billing fails" do
    OrgCreationJob.expects(:perform_later).never
    GitHub::Billing.expects(:signup).returns(stub(success?: false, error_message: ":("))

    Organization::Creator.perform(@user, GitHub::Plan.bronze, @org_attrs, payment_details: { present: true })
  end

  unless GitHub.single_business_environment?
    test "creates a new organization with a plan-based coupon" do
      coupon = create :coupon,
        plan: GitHub::Plan.business_plus,
        discount: 105 # 5 seats * $21

      only = [AddToSearchIndexJob]
      result = perform_enqueued_jobs(only: only) do
        Organization::Creator.perform \
          @user,
          GitHub::Plan.business_plus,
          @org_attrs.merge(seats: 5),
          coupon_code: coupon.code
      end

      assert result.success?
      assert_equal GitHub::Plan.business_plus, result.organization.plan
    end
  end

  test "does not create a profile if the profile_name attribute and org login are the same" do
    org_attrs = @org_attrs.merge(profile_name: "new-org")

    result = Organization::Creator.perform(@user, GitHub::Plan.free, org_attrs)

    refute result.organization.profile.present?
  end

  test "creates a profile if profile_name attribute and org login are different" do
    org_attrs = @org_attrs.merge(profile_name: "Profile name for new org")

    result = Organization::Creator.perform(@user, GitHub::Plan.free, org_attrs)

    assert_equal "Profile name for new org", result.organization.profile.name
  end

  if GitHub.billing_enabled?
    test "creates a new organization with show_onboarding_tasks enabled" do
      result = Organization::Creator.perform(
        @user,
        GitHub::Plan.free,
        @org_attrs,
      )

      assert result.success?
      assert result.organization.show_onboarding_tasks?
    end

    test "creates a new organization with show_onboarding_tasks enabled if the org belongs to a business" do
      result = Organization::Creator.perform(
        @user,
        GitHub::Plan.free,
        @org_attrs.merge(company_name: @business.name),
        business_owned: true,
        business: @business,
      )

      assert result.success?
      assert result.organization.show_onboarding_tasks?
    end


    test "does not create a new organization with show_onboarding_tasks enabled if business has emu enabled" do
      emu_owner = create :emu, :owner, provider_type: :oidc
      emu_business = emu_owner.enterprise_managed_business
      result = Organization::Creator.perform(
        emu_owner,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: emu_business.name),
        business_owned: true,
        business: emu_business,
      )

      assert result.success?
      refute result.organization.show_onboarding_tasks?
    end

    test "creates a new organization on a paid plan" do
      assert_nil Organization.find_by_login("new-org")

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.business,
          @org_attrs,
          payment_details: zuora_parsed_payment_details
        assert_predicate result, :success?, result.error_message
      end
      org = Organization.find_by_login("new-org")

      refute_nil org
      assert_equal "new-org", org.login
      assert_equal "admin@github.com", org.billing_email
      assert_equal 20, org.seats
      assert_predicate org.terms_of_service, :standard?
      assert_same_elements [@user], org.admins
    end

    test "ignores any plan that may be set in the org attributes" do
      @org_attrs[:plan] = GitHub::Plan.business.to_s

      Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
      org = Organization.find_by_login("new-org")

      assert_equal GitHub::Plan.default_plan, org.plan
    end

    test "require minimum number of seats for business plan" do
      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        Organization::Creator.perform \
          @user,
          GitHub::Plan.business,
          @org_attrs.merge(seats: 1),
          payment_details: zuora_parsed_payment_details
      end

      org = Organization.find_by_login(@org_attrs[:login])

      assert_equal 1, org.seats
    end

    test "does not collect payment immediately for a new organization on a free plan" do
      assert_nil Organization.find_by_login("new-org")

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Organization::Creator.perform(
            @user,
            GitHub::Plan.free,
            @org_attrs,
          )
        end
      end
      org = Organization.find_by_login("new-org")

      refute_nil org
      assert_equal "new-org", org.login
      assert_equal "free", org.plan.name
      assert_equal 0, org.seats
    end

    test "collects payment immediately for a new organization on a paid plan" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      assert_nil Organization.find_by_login("new-org")

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
          with_live_zuora("zuora_subscription/successful_create_account_with_card") do
            result = Organization::Creator.perform \
              @user,
              GitHub::Plan.business,
              @org_attrs,
              payment_details: zuora_parsed_payment_details
            assert_predicate result, :success?, result.error_message
          end
        end
      end
      org = Organization.find_by_login("new-org")

      refute_nil org
      assert_equal "new-org", org.login
      assert_equal "business", org.plan.name
      assert_equal 20, org.seats
    end
  end

  if GitHub.single_business_environment?
    test "adds the org to the global business" do
      GitHub::Enterprise.ensure_business!
      plan = GitHub::Plan.find("enterprise")
      result = Organization::Creator.perform(@user, plan, @org_attrs)
      org = result.organization

      assert_equal GitHub.global_business, org.business
    end

    test "sets the business_id to 0" do
      GitHub::Enterprise.ensure_business!
      plan = GitHub::Plan.find("enterprise")
      result = Organization::Creator.perform(@user, plan, @org_attrs)
      org = result.organization

      assert_equal 0, org.business_id
    end
  end

  context "with a `business`" do
    if GitHub.single_business_environment?
      test "creates the organization and sets plan to enterprise on GHES" do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business

        assert_predicate result, :success?

        organization = result.organization.reload
        assert_same_elements [@user], organization.admins
        assert_equal @business, organization.business
        assert_same_elements @business.reload.organizations, [organization]
        assert_equal GitHub::Plan.enterprise, organization.plan
      end
    else
      test "creates the organization if everything is awesome" do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business

        assert_predicate result, :success?

        organization = result.organization.reload
        assert_same_elements [@user], organization.admins
        assert_equal @business, organization.business
        assert_same_elements @business.reload.organizations, [organization]
        assert_equal GitHub::Plan.business_plus, organization.plan
      end

      test "creates the organization with free plan if business is trial" do
        @business.update(trial_expires_at: 1.month.from_now)
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business

        assert_predicate result, :success?

        organization = result.organization.reload
        assert_same_elements [@user], organization.admins
        assert_equal @business, organization.business
        assert_same_elements @business.reload.organizations, [organization]
        assert_equal GitHub::Plan.business_plus, organization.plan
        assert_equal "free", organization.read_attribute(:plan)
      end
    end

    test "fails if current_user is nil" do
      result = T.let(nil, T.nilable(Organization::Creator::Result))

      assert_no_difference("Organization.count") do
        result = Organization::Creator.perform \
          nil,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
    end

    if GitHub.spamminess_check_enabled?
      test "fails if Business is spammy" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?

        result = assert_no_difference "Organization.count" do
          Organization::Creator.perform \
            @user,
            GitHub::Plan.free,
            @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
            business_owned: true,
            business: @business
        end

        refute_predicate result, :success?
      end
    end

    test "fails if current_user is not a Business owner" do
      user = create :user
      result = T.let(nil, T.nilable(Organization::Creator::Result))

      assert_no_difference("Organization.count") do
        result = Organization::Creator.perform \
          user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
    end

    test "fails if any proposed admins do not meet specified Business two-factor requirement" do
      make_two_factor_credential(@user)
      @business.enable_two_factor_required(actor: @user, force: true)
      assert_predicate @business, :two_factor_requirement_enabled?

      non_two_factor_user = create :user, login: "non-two-factor-user"
      org_hash = @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name)
      org_hash[:admin_logins] = [non_two_factor_user.login]

      result = assert_no_difference("Organization.count") do
        Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          org_hash,
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
    end

    test "works with a business param when all proposed admins meet the Business two-factor requirement" do
      make_two_factor_credential(@user)
      @business.enable_two_factor_required(actor: @user, force: true)
      assert_predicate @business, :two_factor_requirement_enabled?

      other_two_factor_user = create :user, login: "other-two-factor-user"
      make_two_factor_credential(other_two_factor_user)

      org_hash = @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name)
      org_hash[:admin_logins] = [@user.login, other_two_factor_user.login]

      result = Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        org_hash,
        business_owned: true,
        business: @business

      assert_predicate result, :success?
      organization = result.organization.reload
      assert_predicate organization, :two_factor_requirement_enabled?
      assert_same_elements [@user, other_two_factor_user], organization.admins
      assert_equal @business, organization.business
      assert_same_elements @business.reload.organizations, [organization]
    end

    test "fails if the org_params are incomplete" do
      result = T.let(nil, T.nilable(Organization::Creator::Result))

      assert_no_difference("Organization.count") do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:name, :seats, :admin_logins).merge(login: "", company_name: @business.name),
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
      assert_match "Organization name can't be blank", T.must(result).organization.errors.full_messages.join(",")
    end

    test "fails if company_name is too long" do
      result = T.let(nil, T.nilable(Organization::Creator::Result))

      assert_no_difference("Organization.count") do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: "e" * 2000),
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
      assert_equal T.must(result).error_message, "Company name is invalid"
    end

    test "fails if the Organization fails to be added to the Business" do
      Business::OrganizationMembership.any_instance.expects(:persisted?).returns(false).at_least_once

      result = T.let(nil, T.nilable(Organization::Creator::Result))

      assert_no_difference("Organization.count") do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
          business_owned: true,
          business: @business
      end

      refute_predicate result, :success?
    end

    test "creates a BusinessUserAccount record for org admins when creating a new Organization directly in a Business", skip_enterprise: true do
      BusinessUserAccount.delete_all
      refute @business.user_accounts.exists?(user: @business.owners.first)

      assert_difference("BusinessUserAccount.count") do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          Organization::Creator.perform \
            @user,
            GitHub::Plan.free,
            @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
            business_owned: true,
            business: @business
        end
      end

      assert @business.reload.user_accounts.exists?(user: @business.owners.first)
    end

    test "does not create an organization membership entry record for org admins when creating a new organization directly in an enterprise", skip_enterprise: true do
      assert_no_difference ["OrganizationMembershipEntry.count"] do
        result = Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business

        assert_predicate result, :success?

        organization = result.organization.reload
        assert_same_elements [@user], organization.admins
        assert_equal @business, organization.business
        assert_same_elements @business.reload.organizations, [organization]
      end
    end

    test "allows allocating volume license if available", skip_enterprise: true do
      @business.update(seats: 0)
      create(:enterprise_agreement, :visual_studio_bundle, seats: 1, business: @business)

      result = Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business

      assert_predicate result, :success?
    end

    test "allows an organization to be added if there are enough total licenses", skip_enterprise: true do
      @business.update(seats: 0)
      create(:enterprise_agreement, :visual_studio_bundle, seats: 1, business: @business)

      result = Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business

      assert_predicate result, :success?
    end

    test "does not allow allocating volume licenses if none available", skip_enterprise: true do
      @business.update(seats: 0)
      create(:enterprise_agreement, :visual_studio_bundle, seats: 0, business: @business)
      result = Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business

      refute_predicate result, :success?
    end

    test "allows a business owner already taking up a license to create an org when no licenses left", skip_enterprise: true do
      owner = create :user, login: "license-consuming-user"
      org = create :organization, admins: [owner]
      business = create :business, owners: [owner], organizations: [org]
      business.update(seats: 0)

      result = Organization::Creator.perform \
        owner,
        GitHub::Plan.free,
        {
          login: "new-org",
          admin_logins: [owner.login],
          billing_email: "admin@github.com",
          company_name: business.name
        },
        business_owned: true,
        business: business
      assert_predicate result, :success?
    end

    test "does not allow an owner who's not taking up a license to create a license when no licenses left", skip_enterprise: true do
      nonmember_business_owner = create(:user, login: "non-member-business-owner")
      nonmember_business_owner.emails.each(&:verify!)
      @business.add_owner(nonmember_business_owner, actor: @user)

      @business.update(seats: 0)
      create(:enterprise_agreement, :visual_studio_bundle, seats: 0, business: @business)
      result = Organization::Creator.perform \
        nonmember_business_owner,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business

      refute_predicate result, :success?
      assert_equal result.error_message, "Insufficient seats to add this organization (1 seat required to add new-org, 1 more must be purchased for the enterprise account)"
    end

    test "enqueues the enterprise cloud trial check job to display the trial banner" do
      Billing::EnterpriseCloudTrialCheckJob.expects(:perform_later).with do |org_id|
        org_id == Organization.find_by_login("new-org").id
      end

      Organization::Creator.perform \
        @user,
        GitHub::Plan.free,
        @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
        business_owned: true,
        business: @business
    end
  end

  context "instrumentation" do
    if GitHub.enterprise?
      test "instruments org.create" do
        events = subscribe "org.create"
        plan   = GitHub::Plan.find("enterprise")
        result = Organization::Creator.perform(@user, plan, @org_attrs)
        org    = result.organization

        expected_payload = {
          org: org.login,
          org_id: org.id,
          actor: @user.login,
          actor_id: @user.id,
          email: "admin@github.com",
          plan: "enterprise",
          tos_sha: TosAcceptance.current_sha,
        }

        assert event = events.pop, "expected an event"
        assert_equal expected_payload, event.payload
      end
    else
      test "instruments org.create" do
        events = subscribe "org.create"
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs
        org = result.organization

        expected_payload = {
          org: org.login,
          org_id: org.id,
          actor: @user.login,
          actor_id: @user.id,
          email: "admin@github.com",
          plan: "free",
          tos_sha: TosAcceptance.current_sha,
        }

        assert event = events.pop, "expected an event"
        assert_equal expected_payload, event.payload
      end
    end
  end
end

module SharedOrganizationCreatorTests
  extend ActiveSupport::Concern

  def shared_fixtures
    T.bind(self, GitHub::TestCase)
    @business = create(:business, :enterprise_managed)
    @user = create(:emu, business: @business)

    @org_attrs = {
      login: "new-org",
      admin_logins: [@user.login],
      billing_email: "admin@github.com",
    }

    @emu_business_without_owner = create(:business, :enterprise_managed)

    GitHub::CurrentTenant.set(@emu_business_without_owner) if GitHub.multi_tenant_enterprise?
    @admin_user = @emu_business_without_owner.find_first_emu_owner
  end

  included do
    T.bind(self, T.class_of(GitHub::TestCase))

    test "does not enable an EMU to create an Org that isn't associated with an EMU Enterprise" do
      assert_raises Permissions::Participant::PermissionGrantError do
        Organization::Creator.perform(@user, GitHub::Plan.free, @org_attrs)
      end
    end

    test "fails to create an organization or a membership entry record for users when creating a new organization directly in an emu enabled enterprise" do
      assert_no_difference ["OrganizationMembershipEntry.count"] do
        result = Organization::Creator.perform \
          @user,
          GitHub::Plan.free,
          @org_attrs.except(:seats, :admin_logins, :business).merge(company_name: @business.name),
          business_owned: true,
          business: @business

        refute_predicate result, :success?, result
      end
    end

    test "do not allow organizations to be created when enterprise did not setup sso" do
      GitHub::CurrentTenant.set(@emu_business_without_owner) if GitHub.multi_tenant_enterprise?

      org_attrs = {
        login: "new-org",
        admin_logins: [@admin_user.login],
        billing_email: "admin@github.com",
      }

      assert_no_difference ["OrganizationMembershipEntry.count"] do
        result = Organization::Creator.perform \
          @admin_user,
          GitHub::Plan.free,
          org_attrs.except(:seats, :admin_logins, :business).merge(company_name: @emu_business_without_owner.name),
          business_owned: true,
          business: @emu_business_without_owner

        refute_predicate result, :success?, result
        assert_equal Organization::Creator::EMU_NO_SSO_SETUP_ERROR, result.error_message
      end
    end
  end
end

class EmuOrganizationCreatorTest < GitHub::TestCase
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper
  include AuditLogHelpers
  include SharedOrganizationCreatorTests

  fixtures do
    shared_fixtures
  end

  test "creates the organization if everything is awesome in oidc" do
    emu_owner = create :emu, :owner, provider_type: :oidc
    business = emu_owner.enterprise_managed_business

    result = Organization::Creator.perform \
      emu_owner,
      GitHub::Plan.free,
      @org_attrs.except(:seats, :admin_logins).merge(company_name: business.name),
      business_owned: true,
      business: business

    assert_predicate result, :success?

    organization = result.organization.reload
    assert_same_elements [emu_owner], organization.admins
    assert_equal business, organization.business
    assert_same_elements business.reload.organizations, [organization]
    assert_equal GitHub::Plan.business_plus, organization.plan
  end
end unless GitHub.single_business_environment?

class MultiTenantOrganizationCreatorTest < GitHub::TestCase
  include SharedOrganizationCreatorTests

  fixtures do
    on_multi_tenant_enterprise do
      shared_fixtures
      GitHub::CurrentTenant.set(@business)
      @owner = create(:emu, :owner, business: @business)
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  test "creates the organization and sets plan to business plus in Proxima" do
    org_hash = @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name)
    org_hash.merge!({ "force_enterprise_managed" => true, "login_suffix" => @business.shortcode })

    result = Organization::Creator.perform \
      @owner,
      GitHub::Plan.free,
      org_hash,
      business_owned: true,
      business: @business

    assert_predicate result, :success?
    organization = result.organization.reload

    assert_same_elements [@owner], organization.admins
    assert_equal @business, organization.business
    assert_same_elements @business.reload.organizations, [organization]
    assert_equal GitHub::Plan.business_plus, organization.plan

    # display_login set correctly
    assert organization.login.include?(@business.shortcode)
    assert_equal User.to_display_login(organization.login), organization.read_attribute(:display_login)
    refute organization.read_attribute(:display_login).include?(@business.shortcode)
  end

  test "creates the organization with business id matching enterprise" do
    result = Organization::Creator.perform \
      @owner,
      GitHub::Plan.free,
      @org_attrs.except(:seats, :admin_logins).merge(company_name: @business.name),
      business_owned: true,
      business: @business

    assert_predicate result, :success?

    organization = result.organization.reload
    assert_same_elements [@owner], organization.admins
    assert_equal @business, organization.business
    assert_same_elements @business.reload.organizations, [organization]
    assert_equal @business.id, organization.business_id
  end
end unless GitHub.single_business_environment?
