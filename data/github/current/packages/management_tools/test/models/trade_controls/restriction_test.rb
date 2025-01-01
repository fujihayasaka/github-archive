# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsRestrictionTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers
  include AuditLog::IntegrationTestHelpers
  include ActionMailer::TestHelper

  fixtures do
    @staffer = create(:staff_admin_user)
    @unrestricted_user = create(:user, :trade_unrestricted)
    @restricted_user = create(:user, :fully_trade_restricted)
    @unrestricted_org = create(:organization, :trade_unrestricted)
    @fully_restricted_org = create(:organization, :fully_trade_restricted)

    @owner = create(:user, login: "owner")
    @org = create(:organization, admin: @owner)

    @admin_user_1 = create(:user)
    @admin_user_2 = create(:user)
    @admin_user_3 = create(:user)
    @admin_user_4 = create(:user)

    @member_user_1 = create(:user)

    @billing_user_1 = create(:user)
    @billing_user_2 = create(:user)
    @billing_user_3 = create(:user)
    @billing_user_4 = create(:user)

    @outside_user_1 = create(:user)
    @outside_user_2 = create(:user)
    @outside_user_3 = create(:user)
    @outside_user_4 = create(:user)

    @restricted_admin_user_1 = create(:user, :fully_trade_restricted)
    @restricted_admin_user_2 = create(:user, :fully_trade_restricted)
    @restricted_admin_user_3 = create(:user, :fully_trade_restricted)
    @restricted_admin_user_4 = create(:user, :fully_trade_restricted)

    @restricted_member_user_1 = create(:user, :fully_trade_restricted)

    @restricted_billing_user_1 = create(:user, :fully_trade_restricted)
    @restricted_billing_user_2 = create(:user, :fully_trade_restricted)
    @restricted_billing_user_3 = create(:user, :fully_trade_restricted)
    @restricted_billing_user_4 = create(:user, :fully_trade_restricted)

    @restricted_outside_user_1 = create(:user, :fully_trade_restricted)
    @restricted_outside_user_2 = create(:user, :fully_trade_restricted)
    @restricted_outside_user_3 = create(:user, :fully_trade_restricted)
    @restricted_outside_user_4 = create(:user, :fully_trade_restricted)

    @private_repo = create(:private_repository, owner: @org)
  end

  setup do
    skip unless GitHub.billing_enabled?
  end

  test "a duplicate user_id is invalid" do
    duped = @fully_restricted_org.trade_controls_restriction.dup
    duped.update(type: "full")

    assert_equal [:user_id], duped.errors.attribute_names
  end

  test "invalid update does not set global notice" do
    user_restriction = @unrestricted_user.trade_controls_restriction

    assert_raises ActiveRecord::RecordInvalid do
      user_restriction.partial!
    end

    notice = GlobalNoticeNext.new(viewer: @unrestricted_user)
    assert_nil notice.current_notice_name
  end

  context "unpersisted (new) records" do
    test "are saved during state transition" do
      restriction = create(:user).build_trade_controls_restriction
      refute_predicate restriction, :persisted?

      restriction.enforce!(compliance: TradeControls::NullCompliance.new)
      assert_predicate restriction, :persisted?
    end
  end

  context "#has_override_within_last_6_months?" do
    test "returns false if last_override_date is nil" do
      user = create(:user, :fully_trade_restricted)
      assert_predicate user.trade_controls_restriction, :full?
      refute_predicate user.trade_controls_restriction, :has_override_within_last_6_months?
    end

    test "returns false if last_override_date is not within the last 6 months" do
      user = create(:user, :fully_trade_restricted)
      user.trade_controls_restriction.update(last_override_date: 6.months.ago)

      assert_predicate user.trade_controls_restriction, :full?
      refute_predicate user.trade_controls_restriction, :has_override_within_last_6_months?
    end

    test "returns true if last_override_date is within the last 6 months" do
      user = create(:user, :fully_trade_restricted)
      user.trade_controls_restriction.update(last_override_date: 5.months.ago)

      assert_predicate user.trade_controls_restriction, :full?
      assert_predicate user.trade_controls_restriction, :has_override_within_last_6_months?
    end
  end

  context "#can_override_automatically?" do
    test "returns false if restricted_on_creation is true" do
      user = create(:user, :fully_trade_restricted)
      restriction = user.trade_controls_restriction
      restriction.update(restricted_on_creation: true)

      assert_predicate restriction, :full?
      assert_predicate restriction, :restricted_on_creation?
      refute_predicate restriction, :can_override_automatically?
    end

    test "returns false if restricted_on_creation is false but user create date and restriction create date are the same" do
      user = create(:user, :fully_trade_restricted, created_at: 2.months.ago)
      restriction = user.trade_controls_restriction
      restriction.update(enforcement_reason: "ip", restricted_on_creation: false, created_at: 2.months.ago, last_override_date: 6.months.ago)

      refute restriction.restricted_on_creation
      assert_equal user.created_at.to_date, restriction.created_at.to_date
      assert_predicate restriction, :restricted_on_creation?
      refute_predicate restriction, :can_override_automatically?
    end

    test "returns false if account was created within the last 30 days" do
      user = create(:user, :fully_trade_restricted)
      restriction = user.trade_controls_restriction

      assert_predicate restriction, :full?
      assert_predicate restriction, :has_insufficient_account_age?
      refute_predicate restriction, :can_override_automatically?
    end

    test "returns false if last_override_date is within the last 6 months" do
      user = create(:user, :fully_trade_restricted, created_at: 2.months.ago)
      restriction = user.trade_controls_restriction
      restriction.update(last_override_date: 5.months.ago)

      assert_predicate restriction, :full?
      assert_predicate restriction, :has_override_within_last_6_months?
      refute_predicate restriction, :can_override_automatically?
    end

    test "returns false if enforcement_reason is not ip" do
      user = create(:user, :fully_trade_restricted, created_at: 2.months.ago)
      restriction = user.trade_controls_restriction
      restriction.update(enforcement_reason: "manual")

      assert_predicate restriction, :full?
      refute_predicate restriction, :can_override_automatically?
    end

    test "returns true if actor wasn't restricted on creation, created more than a month ago, last override date is 6 months and above, and enforcement reason is IP" do
      user = create(:user, :verified)

      Timecop.travel(2.months.from_now) do
        user.trade_controls_restriction.update(type: "full", enforcement_reason: "ip", restricted_on_creation: false, last_override_date: 7.months.ago)
        restriction = user.reload.trade_controls_restriction

        assert_predicate restriction, :full?
        refute_predicate restriction, :restricted_on_creation?
        refute_predicate restriction, :has_insufficient_account_age?
        refute_predicate restriction, :has_override_within_last_6_months?
        assert_equal "ip", restriction.enforcement_reason
        assert_predicate restriction, :can_override_automatically?
      end
    end
  end

  context "#valid_events_with_subsequent_state" do
    test "does not return unrestrict event/state for an unflagged org" do
      org = create(:organization)
      events = org.trade_controls_restriction.valid_events_with_subsequent_state.flatten

      assert events.present?

      refute_includes events, :unrestricted
      refute_includes events, :override

      assert_includes events, :partially_enforce
      assert_includes events, :enforce
    end

    test "does not return :partial for users" do
      user = create(:user)
      events = user.trade_controls_restriction.valid_events_with_subsequent_state.flatten

      assert events.present?

      refute_includes events, :unrestricted
      refute_includes events, :override
      refute_includes events, :partially_enforce

      assert_includes events, :enforce

    end

    test "does not return nil for users events" do
      user = create(:user)
      events = user.trade_controls_restriction.valid_events_with_subsequent_state

      assert events.present?

      refute_includes events, nil

    end
  end

  test "only Organizations may be partially restricted" do
    user_restriction = @restricted_user.trade_controls_restriction
    assert_raises ActiveRecord::RecordInvalid do
      user_restriction.partial!
    end

    org_restriction = @unrestricted_org.trade_controls_restriction
    org_restriction.partial!
    assert_predicate org_restriction, :valid?
  end

  test "only Organizations may be tier_0 restricted" do
    user_restriction = @restricted_user.trade_controls_restriction
    assert_raises ActiveRecord::RecordInvalid do
      user_restriction.tier_0!
    end

    org_restriction = @unrestricted_org.trade_controls_restriction
    org_restriction.tier_0!
    assert_predicate org_restriction, :valid?
  end

  test "only Organizations may be tier_1 restricted" do
    user_restriction = @restricted_user.trade_controls_restriction
    assert_raises ActiveRecord::RecordInvalid do
      user_restriction.tier_1!
    end

    org_restriction = @unrestricted_org.trade_controls_restriction
    org_restriction.tier_1!
    assert_predicate org_restriction, :valid?
  end

  test "it reports to dogstats if country code is updated" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @unrestricted_user.trade_controls_restriction.save!
    @unrestricted_user.trade_controls_restriction.update(trade_restricted_country_code: "IRN")

    expected_tags = [
      "country_code_was:",
      "country_code_is:IRN"
    ]
    assert_equal 1, stats.increments("trade_controls_restriction.country_code.update", tags: expected_tags).count
  end

  context "#enforce!" do
    test "enforces and saves contextual data for the restriction record", skip_enterprise: true do
      expected_event = "trade_controls_restriction.enforce"
      user = create(:user, login: "crimea-user", plan: "pro")

      GitHub::Location.stubs(:look_up).with("IP from Crimea").returns({ country_code: "UA", region_name: "Crimea" })
      Timecop.freeze(Time.utc(2022, 1, 1, 12, 0, 0)) do
        perform_enqueued_jobs(only: ::TradeControls::ComplianceCheckJob) do
          GlobalInstrumenter.instrument "user.signup.ip_update", {
            actor: user,
            actor_ip: "IP from Crimea",
            signup_email: user.emails.first,
          }
        end

        restriction = user.reload.trade_controls_restriction
        assert_equal "full", restriction.type
        assert_equal "UKR -- Crimea", restriction.trade_restricted_country_code
        assert_equal "ip", restriction.enforcement_reason
        assert_predicate restriction, :restricted_on_creation
        assert_equal restriction.last_enforcement_date, Time.utc(2022, 1, 1, 12, 0, 0)
        assert_nil restriction.last_override_date
        assert_nil restriction.metadata

        expected_tags = [
          "country_code:UA",
          "reason:ip",
          "restriction_type:full",
          "restriction_type_was:unrestricted",
          "owner_type:USER"
        ]
        assert_dogstats_increment(expected_event, tags: expected_tags)

        assert_hydro_published({
          account: Hydro::EntitySerializer.user(user),
          reason: "IP_ADDRESS",
          country: "Ukraine",
          region: "Crimea",
          ip_address: "IP from Crimea",
          email_address: nil,
          restricted_on_creation: true,
          last_enforcement_date: restriction.last_enforcement_date,
          last_override_date: restriction.last_override_date,
        }, schema: "github.trade_restrictions.v0.TradeRestrictionFlag")
      end
    end

    test "creates a scheduled downgrade" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      refute OFACDowngrade.find_by(user_id: @unrestricted_user.id)

      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)

      assert OFACDowngrade.find_by(user_id: @unrestricted_user.id)
    end

    test "publishes a hydro event for the user", skip_enterprise: true do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)

      restriction = @unrestricted_user.reload.trade_controls_restriction
      assert_hydro_published({
        account: Hydro::EntitySerializer.user(@unrestricted_user),
        reason: :EMAIL,
        country: "Syria",
        region: nil,
        ip_address: nil,
        email_address: "test@test.sy",
        restricted_on_creation: false,
        last_enforcement_date: restriction.last_enforcement_date,
        last_override_date: restriction.last_override_date,
      }, schema: "github.trade_restrictions.v0.TradeRestrictionFlag")
    end

    test "enqueues instrument job for orgs", skip_enterprise: true do
      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "A good reason")

      assert_enqueued_with job: InstrumentOrganizationTradeRestrictionEnforceJob do
        @unrestricted_org.trade_controls_restriction.enforce!(compliance: compliance)
      end
    end

    test "sends a restriction email" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_includes ActionMailer::Base.deliveries.first.to, @unrestricted_user.email
      assert_equal "GitHub and Trade Controls", ActionMailer::Base.deliveries.first.subject
    end

    test "doesn't send a restriction email when skip_enforcement_email is true" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      assert_no_emails do
        @unrestricted_user.trade_controls_restriction.enforce! \
          compliance: compliance,
          skip_enforcement_email: true
      end
    end

    test "suspends the user's general-purpose plan subscription", skip_enterprise: true do
      plan_subscription = create(:billing_plan_subscription)
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      user = plan_subscription.user

      assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [plan_subscription]) do
        user.trade_controls_restriction.enforce!(compliance: compliance)
      end
    end

    test "suspends the user's sponsors-purpose plan subscription", skip_enterprise: true do
      sponsors_plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced)
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      user = sponsors_plan_subscription.user

      assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [sponsors_plan_subscription]) do
        user.trade_controls_restriction.enforce!(compliance: compliance)
      end
    end

    test "zeroes out the users invoices", skip_enterprise: true do
      user = create(:user, :zuora)
      plan_subscription = create(:billing_plan_subscription, user: user)

      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      Billing::Zuora::ZeroOutInvoices.expects(:for_subscription).returns(::GitHub::Billing::Result.success)

      perform_enqueued_jobs(only: SuspendPlanSubscriptionJob) do
        user.trade_controls_restriction.enforce!(compliance: compliance)
      end
    end

    test "unpublishes the user's private pages" do
      user = create(:user, plan: "pro")
      public_repo = create(:repository, owner: user)
      create(:page, repository: public_repo)
      private_repo = create(:private_repository, owner: user)
      create(:page, repository: private_repo)
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      user.trade_controls_restriction.enforce!(compliance: compliance)

      [public_repo, private_repo, user].map(&:reload)
      assert public_repo.page
      assert_nil private_repo.page
    end

    test "it populates trade_restricted_country_code for user" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)

      assert @unrestricted_user.trade_controls_restriction.trade_restricted_country_code.present?
      assert_equal @unrestricted_user.trade_controls_restriction.trade_restricted_country_code, "SYR"
    end

    test "it populates trade_restricted_country_code for organization" do
      expected_event = "trade_controls_restriction.enforce"
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")
      @unrestricted_org.trade_controls_restriction.enforce!(compliance: compliance)

      expected_tags = [
        "country_code:SY",
        "reason:email",
        "restriction_type:full",
        "restriction_type_was:unrestricted",
        "owner_type:ORGANIZATION"
      ]
      assert_dogstats_increment(expected_event, tags: expected_tags)

      assert @unrestricted_org.trade_controls_restriction.trade_restricted_country_code.present?
      assert_equal @unrestricted_org.trade_controls_restriction.trade_restricted_country_code, "SYR"
    end

    test "it sets global notice for user" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)

      notice = GlobalNoticeNext.new(viewer: @unrestricted_user)
      assert notice.current_notice
      assert_equal :ofac_flagged, notice.current_notice_name
      assert notice.current_notice.should_show_notice?
    end

    test "it sets global notice for organization" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      @unrestricted_org.trade_controls_restriction.enforce!(compliance: compliance)

      notice = GlobalNoticeNext.new(viewer: @unrestricted_org)
      assert notice.current_notice
      assert_equal :ofac_flagged, notice.current_notice_name
      assert notice.current_notice.should_show_notice?
    end

    test "if country code or region is not available it does not update trade_restricted_country_code" do
      [@admin_user_1, @admin_user_2, @admin_user_3, @restricted_admin_user_1, @restricted_admin_user_2, @restricted_admin_user_3].each do |u|
        @org.add_admin(u)
      end

      compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org)
      @org.trade_controls_restriction.enforce!(compliance: compliance)

      restriction = @org.trade_controls_restriction
      assert_predicate restriction, :persisted?
      assert_predicate restriction, :full?
      assert restriction.trade_restricted_country_code.blank?
    end

    test "orgs can move to full restriction from partial and does not send email" do
      org = create(:organization)
      org.trade_controls_restriction.partial!

      assert_predicate org.trade_controls_restriction, :partial?

      TradeControlsMailer.expects(:organization_restricted).never

      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "suspension")
      org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_predicate org.reload.trade_controls_restriction, :full?
    end

    test "orgs can move to full restriction from tier_0 and does not send email" do
      org = create(:organization)
      org.trade_controls_restriction.tier_0!

      assert_predicate org.trade_controls_restriction, :tier_0?

      TradeControlsMailer.expects(:organization_restricted).never

      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "suspension")
      org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_predicate org.reload.trade_controls_restriction, :full?
    end

    test "orgs can move to full restriction from tier_1 and does not send email" do
      org = create(:organization)
      org.trade_controls_restriction.tier_1!

      assert_predicate org.trade_controls_restriction, :tier_1?

      TradeControlsMailer.expects(:organization_restricted).never

      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "suspension")
      org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_predicate org.reload.trade_controls_restriction, :full?
    end

    test "sends email on full restriction entry when org is currently unrestricted" do
      assert_predicate @org.trade_controls_restriction, :unrestricted?

      ActionMailer::Base.deliveries.clear

      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "suspension")
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @org.trade_controls_restriction.enforce!(compliance: compliance)
      end
      assert_predicate @org.reload.trade_controls_restriction, :full?

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_includes ActionMailer::Base.deliveries.first.to, @org.billing_email
      assert_equal "GitHub and Trade Controls", ActionMailer::Base.deliveries.first.subject
    end
  end

  context "#partially_enforce!" do
    test "does not send an email" do
      TradeControlsMailer.expects(:organization_restricted).never
      @unrestricted_org.trade_controls_restriction.partially_enforce!(
        compliance: TradeControls::ManualCompliance.new(actor: @staffer))
    end

    test "it sets global notice for organization" do
      compliance = TradeControls::EmailCompliance.new(email: "test@test.sy")

      @unrestricted_org.trade_controls_restriction.partially_enforce!(compliance: compliance)

      notice = GlobalNoticeNext.new(viewer: @unrestricted_org)
      assert notice.current_notice
      assert_equal :ofac_flagged, notice.current_notice_name
      assert notice.current_notice.should_show_notice?
    end
  end

  context "#tier_0_enforce!" do
    test "transitions from unrestricted to tier_0" do
      assert @unrestricted_org.trade_controls_restriction.unrestricted?

      @unrestricted_org.trade_controls_restriction.tier_0_enforce!(
        compliance: TradeControls::ManualCompliance.new(actor: @staffer))

      assert @unrestricted_org.trade_controls_restriction.tier_0?
    end
  end

  context "#tier_1_enforce!" do
    test "transitions from unrestricted to tier_1" do
      assert @unrestricted_org.trade_controls_restriction.unrestricted?

      @unrestricted_org.trade_controls_restriction.tier_1_enforce!(
        compliance: TradeControls::ManualCompliance.new(actor: @staffer))

      assert @unrestricted_org.trade_controls_restriction.tier_1?
    end
  end

  context "#override!" do
    test "overrides and saves contextual data for the restriction record", skip_enterprise: true do
      enforcement_date = Time.utc(2022, 1, 1, 12, 0, 0)
      restricted_user = Timecop.freeze(enforcement_date) do
        user = create(:user, login: "crimea-user", plan: "pro")
        location = { country_code: "UA", region_name: "Crimea" }
        compliance = TradeControls::IpCompliance.new(ip: "IP from Crimea", location: location)

        user.trade_controls_restriction.enforce!(compliance: compliance)
        user
      end

      restriction = restricted_user.reload.trade_controls_restriction
      assert_equal "full", restriction.type
      assert_equal "UKR -- Crimea", restriction.trade_restricted_country_code
      assert_equal "ip", restriction.enforcement_reason
      refute_predicate restriction, :restricted_on_creation
      assert_equal restriction.last_enforcement_date, enforcement_date
      assert_nil restriction.last_override_date
      assert_nil restriction.metadata

      expected_event = "trade_controls_restriction.override"
      expected_payload = {
        restriction_type: :unrestricted,
        restriction_type_was: :full,
        user: restricted_user.login,
        user_id: restricted_user.id,
        reason: "feeling nice",
        actor: @staffer.login,
        actor_id: @staffer.id,
      }

      override_date = Time.utc(2022, 1, 2, 12, 0, 0)
      Timecop.freeze(override_date) do
        actual_payload = assert_performed_audit_entries only: [expected_event] do
          restricted_user.trade_controls_restriction.override!(
            compliance: TradeControls::ManualCompliance.new(actor: @staffer, reason: "feeling nice"))
        end.pop

        restriction = restricted_user.reload.trade_controls_restriction
        assert_nil restriction.trade_restricted_country_code
        assert_nil restriction.enforcement_reason
        assert_equal "unrestricted", restriction.type
        refute_predicate restriction, :restricted_on_creation
        assert_equal restriction.last_enforcement_date, enforcement_date
        assert_equal restriction.last_override_date, override_date
        assert_equal "feeling nice", restriction.metadata["reason"]

        assert_subset_hash expected_payload, actual_payload
        assert_audit_entry_hidden actual_payload

        expected_tags = [
          "reason:manual",
          "restriction_type:unrestricted",
          "restriction_type_was:full"
        ]
        assert_dogstats_increment(expected_event, tags: expected_tags)
      end
    end

    test "destroys the scheduled OFAC downgrade" do
      downgrade = create(:ofac_downgrade)
      user = downgrade.user
      compliance = TradeControls::ManualCompliance.new(actor: @staffer)

      assert user.trade_controls_restriction.override!(compliance: compliance)
      assert_nil OFACDowngrade.find_by(id: downgrade.id)
    end

    test "publishes a hydro event for users", skip_enterprise: true do
      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "traveling")

      @restricted_user.trade_controls_restriction.override!(compliance: compliance)
      restriction = @restricted_user.reload.trade_controls_restriction

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(@restricted_user),
        actor: Hydro::EntitySerializer.user(@staffer),
        reason: "traveling",
        restricted_on_creation: false,
        last_enforcement_date: restriction.last_enforcement_date,
        last_override_date: restriction.last_override_date,
      }, schema: "github.trade_restrictions.v0.TradeRestrictionUnflag")
    end

    test "publishes a hydro event for orgs", skip_enterprise: true do
      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "traveling")

      @fully_restricted_org.trade_controls_restriction.override!(compliance: compliance)
      restriction = @fully_restricted_org.reload.trade_controls_restriction

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(@fully_restricted_org),
        actor: Hydro::EntitySerializer.user(@staffer),
        reason: "traveling",
        restricted_on_creation: false,
        last_enforcement_date: restriction.last_enforcement_date,
        last_override_date: restriction.last_override_date,
      }, schema: "github.trade_restrictions.v0.TradeRestrictionUnflag")
    end

    test "sends a successful appeals process email when individual actor" do
      ActionMailer::Base.deliveries.clear
      compliance = TradeControls::ManualCompliance.new(actor: @staffer)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @restricted_user.trade_controls_restriction.override!(compliance: compliance)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_includes ActionMailer::Base.deliveries.first.to, @restricted_user.email
      assert_equal "GitHub and Trade Controls", ActionMailer::Base.deliveries.first.subject
    end

    test "sends a successful appeals process email when organization actor" do
      ActionMailer::Base.deliveries.clear
      compliance = TradeControls::ManualCompliance.new(actor: @unrestricted_org)

      @unrestricted_org.trade_controls_restriction.full!
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @unrestricted_org.trade_controls_restriction.override!(compliance: compliance)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first
      assert_includes mail.to.to_a, @unrestricted_org.billing_email
      assert_includes mail.to.to_a, @unrestricted_org.admins.first.email
      assert_equal "GitHub and Trade Controls", mail.subject
    end

    test "it removes global notice for user" do
      ActionMailer::Base.deliveries.clear
      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "traveling")

      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @unrestricted_user.trade_controls_restriction.override!(compliance: compliance)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      notice = GlobalNoticeNext.new(viewer: @unrestricted_user)
      assert notice.current_notice
      assert_equal :ofac_flagged, notice.current_notice_name
      assert !notice.current_notice.should_show_notice?
    end

    test "it removes global notice for organization" do
      ActionMailer::Base.deliveries.clear
      compliance = TradeControls::ManualCompliance.new(actor: @staffer, reason: "traveling")

      @unrestricted_org.trade_controls_restriction.enforce!(compliance: compliance)
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @unrestricted_org.trade_controls_restriction.override!(compliance: compliance)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      notice = GlobalNoticeNext.new(viewer: @unrestricted_org)
      assert notice.current_notice
      assert_equal :ofac_flagged, notice.current_notice_name
      assert !notice.current_notice.should_show_notice?
    end

    test "resumes the user's general-purpose plan subscription" do
      plan_subscription = create(:billing_plan_subscription, user: @restricted_user)
      compliance = TradeControls::ManualCompliance.new(actor: @staffer)

      assert_enqueued_with(job: ResumePlanSubscriptionJob, args: [plan_subscription]) do
        @restricted_user.trade_controls_restriction.override!(compliance: compliance)
      end
    end

    test "resumes the user's sponsors-purpose plan subscription" do
      sponsors_plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced, user: @restricted_user)
      compliance = TradeControls::ManualCompliance.new(actor: @staffer)

      assert_enqueued_with(job: ResumePlanSubscriptionJob, args: [sponsors_plan_subscription]) do
        @restricted_user.trade_controls_restriction.override!(compliance: compliance)
      end
    end

    test "un-bans sponsors listing" do
      listing = create(:sponsors_listing, :banned, sponsorable: @restricted_user,
        banned_by: @staffer, banned_reason: "OFAC")

      compliance = TradeControls::ManualCompliance.new(actor: @staffer)
      @restricted_user.trade_controls_restriction.override!(compliance: compliance)

      assert_predicate listing.reload, :waitlisted?
      assert_nil listing.reload_stafftools_metadata.banned_by
      assert_nil listing.stafftools_metadata.banned_reason
    end

    test "is successful if user has no sponsors listing" do
      compliance = TradeControls::ManualCompliance.new(actor: @staffer)
      @restricted_user.trade_controls_restriction.override!(compliance: compliance)

      refute_predicate @restricted_user.reload, :has_any_trade_restrictions?
    end

    test "is successful if user has an waitlisted sponsors listing" do
      user = create(:user)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: user)

      assert_predicate listing, :waitlisted?
      refute_predicate listing, :banned?

      user.trade_controls_restriction.full!

      compliance = TradeControls::ManualCompliance.new(actor: @staffer)
      user.trade_controls_restriction.override!(compliance: compliance)

      refute_predicate user.reload, :has_any_trade_restrictions?
    end

    test "is successful if user has been accepted into Sponsors program" do
      user = create(:user)
      listing = create(:sponsors_listing, sponsorable: user)

      assert_predicate listing, :accepted_into_sponsors?
      refute_predicate listing, :banned?

      user.trade_controls_restriction.full!

      compliance = TradeControls::ManualCompliance.new(actor: @staffer)
      user.trade_controls_restriction.override!(compliance: compliance)

      refute_predicate user.reload, :has_any_trade_restrictions?
    end

    test "is successful if user has an banned sponsors listing" do
      user = create(:user)
      listing = create(:sponsors_listing, :banned, sponsorable: user)

      assert_predicate listing, :banned?

      user.trade_controls_restriction.full!

      compliance = TradeControls::ManualCompliance.new(actor: @staffer)
      user.trade_controls_restriction.override!(compliance: compliance)

      refute_predicate user.reload, :has_any_trade_restrictions?
    end
  end

  context "instruments", skip_enterprise: true do
    include AuditLog::IntegrationTestHelpers
    include DogstatsTestHelpers

    test "reports to Datadog and Sentry when transitioning from one state to the other fails" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      errors = ActiveModel::Errors.new(TradeControls::Restriction.new)
      errors.add(:type)
      TradeControls::Restriction.any_instance.stubs(:errors).returns(errors)

      TradeControls::Restriction.any_instance.expects(:save).once.returns(false)
      location = {
        country_code: "UA",
        region_name: "Donetsk Oblast",
        city: "Makiivka"
      }
      events = assert_performed_audit_entries(count: 0, only: "trade_controls_restriction.enforce") do
        @unrestricted_user.trade_controls_restriction.enforce!(
          compliance: TradeControls::IpCompliance.new(ip: "IP from Makiivka", location: location))
      end
      assert events.empty?

      expected_tags = ["actor:#{@unrestricted_user.display_login}", "from:unrestricted", "to:full", "reason:ip", "error:Type is invalid"]
      assert_dogstats_increment("trade_controls_restriction.failed_transition", tags: expected_tags)
      @unrestricted_user.reload
      refute @unrestricted_user.has_any_trade_restrictions?

      needle = Failbot.reports.last
      assert_equal "TradeControls::Restriction::FailedTransitionError", Failbot.exception_classname_from_hash(needle)
      assert_equal "Failed to transition from unrestricted to full", Failbot.exception_message_from_hash(needle)
    end

    test "reports to dogstats on :ip full enforcement" do
      expected_event = "trade_controls_restriction.enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      location = {
        country_code: "UA",
        region_name: "Crimea",
      }
      compliance = TradeControls::IpCompliance.new(ip: "IP from Crimea", location: location)

      assert_predicate compliance, :violation?
      assert_query_count_per_table({
        trade_controls_restrictions: 4 # 2 selects (1 select from the initial load, 1 select from calling reload in model), 2 updates (1 update to set the restrictions, 1 update to set the metadata)
      }, backtrace_lines: 5) do
        @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)
      end
      assert_dogstats_increment(expected_event, tags: ["country_code:UA", "reason:ip"])
    end

    test "reports to dogstats on :ip partial enforcement" do
      expected_event = "trade_controls_restriction.partially_enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      location = {
        country_code: "UA",
        region_name: "Crimea",
      }
      compliance = TradeControls::IpCompliance.new(ip: "IP from Crimea", location: location)

      assert_predicate compliance, :violation?
      @unrestricted_org.trade_controls_restriction.partially_enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["country_code:UA", "reason:ip"])
    end

    test "reports to dogstats on :email full enforcement" do
      expected_event = "trade_controls_restriction.enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      compliance = TradeControls::EmailCompliance.new(email: "test@example.sy")
      @unrestricted_user.trade_controls_restriction.enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["country_code:SY", "reason:email"])
    end

    test "reports to dogstats on :email partial enforcement" do
      expected_event = "trade_controls_restriction.partially_enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      compliance = TradeControls::EmailCompliance.new(email: "test@example.sy")
      @unrestricted_org.trade_controls_restriction.partially_enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["country_code:SY", "reason:email"])
    end

    test "reports to dogstats on :organization_admin full enforcement" do
      expected_event = "trade_controls_restriction.enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      [@admin_user_1, @admin_user_2, @admin_user_3, @restricted_admin_user_1, @restricted_admin_user_2, @restricted_admin_user_3].each do |u|
        @org.add_admin(u)
      end
      compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org)
      @org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:organization_admin"])
    end

    test "reports to dogstats on :organization_admin partial enforcement" do
      expected_event = "trade_controls_restriction.partially_enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      [@admin_user_1, @admin_user_2, @admin_user_3, @restricted_admin_user_1, @restricted_admin_user_2, @restricted_admin_user_3].each do |u|
        @org.add_admin(u)
      end
      compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org)
      @org.trade_controls_restriction.partially_enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:organization_admin"])
    end

    test "reports to dogstats on :organization_billing_manager full enforcement" do
      expected_event = "trade_controls_restriction.enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      [@billing_user_1, @billing_user_2, @billing_user_3, @billing_user_3, @restricted_billing_user_1, @restricted_billing_user_2, @restricted_billing_user_3].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end
      compliance = TradeControls::BillingManagersCompliance.new(organization: @org)
      @org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:organization_billing_manager"])
    end

    test "reports to dogstats on :organization_billing_manager partial enforcement" do
      expected_event = "trade_controls_restriction.partially_enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      [@billing_user_1, @billing_user_2, @billing_user_3, @billing_user_3, @restricted_billing_user_1, @restricted_billing_user_2, @restricted_billing_user_3].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end
      compliance = TradeControls::BillingManagersCompliance.new(organization: @org)
      @org.trade_controls_restriction.partially_enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:organization_billing_manager"])
    end


    test "reports to dogstats on :website_url full enforcement" do
      expected_event = "trade_controls_restriction.enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "my-blog.sy")
      @org.trade_controls_restriction.enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:website_url"])
    end

    test "reports to dogstats on :website_url partial enforcement" do
      expected_event = "trade_controls_restriction.partially_enforce"
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "my-blog.sy")
      @org.trade_controls_restriction.partially_enforce!(compliance: compliance)
      assert_dogstats_increment(expected_event, tags: ["reason:website_url"])
    end

    test "#enforce" do
      expected_event = "trade_controls_restriction.enforce"
      expected_payload = {
        restriction_type: :full,
        restriction_type_was: :unrestricted,
        user: @unrestricted_user.login,
        user_id: @unrestricted_user.id,
        reason: :email,
        email: "test@example.sy",
        country: "Syria",
        country_code: "SY",
      }

      actual_payload = assert_performed_audit_entries only: [expected_event] do
        @unrestricted_user.trade_controls_restriction.enforce!(
          compliance: TradeControls::EmailCompliance.new(email: "test@example.sy"))
      end.pop

      assert_subset_hash expected_payload, actual_payload
      assert_audit_entry_hidden actual_payload
      assert_dogstats_increment(expected_event, tags: ["country_code:SY", "reason:email", "restriction_type:full", "restriction_type_was:unrestricted"])
    end

    test "#enforce with city instrumentation" do
      expected_event = "trade_controls_restriction.enforce"
      expected_payload = {
        restriction_type: :full,
        restriction_type_was: :unrestricted,
        user: @unrestricted_user.login,
        user_id: @unrestricted_user.id,
        ip: "IP from Makiivka",
        reason: :ip,
        country: "Ukraine",
        country_code: "UA",
        region: "Donetsk Oblast",
        region_code: "14",
        city: "Makiivka"
      }

      location = {
        country_code: "UA",
        region_name: "Donetsk Oblast",
        city: "Makiivka"
      }

      actual_payload = assert_performed_audit_entries only: [expected_event] do
        @unrestricted_user.trade_controls_restriction.enforce!(
          compliance: TradeControls::IpCompliance.new(ip: "IP from Makiivka", location: location))
      end.pop

      assert_subset_hash expected_payload, actual_payload
      assert_audit_entry_hidden actual_payload
      assert_dogstats_increment(expected_event, tags: ["country_code:UA", "reason:ip", "restriction_type:full", "restriction_type_was:unrestricted"])
    end

    test "#partially_enforce" do
      expected_event = "trade_controls_restriction.partially_enforce"
      expected_payload = {
        restriction_type: :partial,
        restriction_type_was: :unrestricted,
        org: @unrestricted_org.login,
        org_id: @unrestricted_org.id,
        reason: "just because",
        actor: @staffer.login,
        actor_id: @staffer.id,
      }

      actual_payload = assert_performed_audit_entries only: [expected_event] do
        @unrestricted_org.trade_controls_restriction.partially_enforce!(
          compliance: TradeControls::ManualCompliance.new(actor: @staffer, reason: "just because"))
      end.pop

      assert_subset_hash expected_payload, actual_payload
      assert_audit_entry_hidden actual_payload
      assert_dogstats_increment(expected_event, tags: ["reason:manual", "restriction_type:partial", "restriction_type_was:unrestricted"])
    end

    test "#override" do
      expected_event = "trade_controls_restriction.override"
      expected_payload = {
        restriction_type: :unrestricted,
        restriction_type_was: :full,
        user: @restricted_user.login,
        user_id: @restricted_user.id,
        reason: "feeling nice",
        actor: @staffer.login,
        actor_id: @staffer.id,
      }

      actual_payload = assert_performed_audit_entries only: [expected_event] do
        @restricted_user.trade_controls_restriction.override!(
          compliance: TradeControls::ManualCompliance.new(actor: @staffer, reason: "feeling nice"))
      end.pop

      assert_subset_hash expected_payload, actual_payload
      assert_audit_entry_hidden actual_payload
      assert_dogstats_increment(expected_event, tags: ["reason:manual", "restriction_type:unrestricted", "restriction_type_was:full"])
    end

    test "#enforce with skip_enforcement_email" do
      expected_event = "trade_controls_restriction.enforce"
      expected_payload = {
        restriction_type: :full,
        restriction_type_was: :unrestricted,
        user: @unrestricted_user.login,
        user_id: @unrestricted_user.id,
        reason: :email,
        email: "test@example.sy",
        country: "Syria",
        country_code: "SY",
      }

      actual_payload = assert_performed_audit_entries only: [expected_event] do
        @unrestricted_user.trade_controls_restriction.enforce! \
          compliance: TradeControls::EmailCompliance.new(email: "test@example.sy"),
          skip_enforcement_email: true
      end.pop

      assert_subset_hash expected_payload, actual_payload
      assert_audit_entry_hidden actual_payload
      assert_dogstats_increment expected_event,
        tags: ["country_code:SY", "reason:email", "restriction_type:full", "restriction_type_was:unrestricted", "skip_enforcement_email:true"]
    end
  end

  context "scopes" do
    test "any_restricted_ids returns correct number of restricted ids" do
      ids = [@restricted_admin_user_1.id, @restricted_member_user_1.id, @restricted_billing_user_1.id, @restricted_outside_user_1.id]
      assert_equal TradeControls::Restriction.any_restricted_ids(ids).count, 4
    end

    test "full_restricted_ids returns correct number of restricted ids" do
      full_restricted_org_1 = create(:organization, :fully_trade_restricted)
      full_restricted_org_2 = create(:organization, :fully_trade_restricted)
      full_restricted_org_3 = create(:organization, :fully_trade_restricted)
      partial_restricted_org = create(:organization, :partially_trade_restricted)
      unrestricted_org = create(:organization, :trade_unrestricted)

      ids = [full_restricted_org_1.id, full_restricted_org_2.id, full_restricted_org_3.id, partial_restricted_org.id, unrestricted_org.id]
      assert_equal TradeControls::Restriction.full_restricted_ids(ids).count, 3
    end
  end

  def assert_audit_entry_hidden(payload)
    AuditLogEntry.new_from_hash(payload).tap do |entry|
      assert_predicate entry, :hidden_from_users?
      assert_predicate entry, :hidden_from_orgs?
      assert_predicate entry, :hidden_from_businesses?
    end
  end
end
