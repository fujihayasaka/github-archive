# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessCreatorTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10, admins: [@org_admin])
    @billing_email = create(:user_email, :verified, user: @org_admin)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "validations" do
    test "require business parameters" do
      c = Business::Creator.new(
        organization: @org,
        business_params: nil,
        actor: @org_admin)
      refute c.valid?
      assert_equal c.error_message, "An enterprise account is required for the #{GitHub::Plan.business_plus.titleized_display_name} plan"
    end

    test "requires business plus plan" do
      org = create(:organization, plan: GitHub::Plan.business, seats: 10, admins: [@org_admin])
      c = Business::Creator.new(
        organization: org,
        business_params: { foo: "bar" },
        actor: @org_admin)
      refute c.valid?
      assert_equal c.error_message, "Enterprise accounts can only be created on the #{GitHub::Plan.business_plus.titleized_display_name} plan"
    end

    test "requires organization not attached to a business" do
      create :business, organizations: [@org]
      c = Business::Creator.new(
        organization: @org.reload,
        business_params: {
          owners: [],
          name: "gibson and sterling, llc",
        },
        actor: @org_admin)
      refute c.valid?
      assert_equal c.error_message, "Organization already belongs to an enterprise"
    end

    test "requires that organization has not initiated an organization to enterprise upgrade" do
      upgraded_business = create :business, owners: [@org_admin]
      @org.upgrade_to_enterprise_in_progress!(upgraded_business)

      c = Business::Creator.new(
        organization: @org.reload,
        business_params: {
          owners: [],
          name: "gibson and sterling, llc",
        },
        actor: @org_admin)
      refute c.valid?
      assert_equal c.error_message, "Organization has already initiated an upgrade to the Enterprise plan"
    end

    test "requires adequate seats" do
      org = create :business_plus_organization,
        seats: 1,
        admin: @org_admin,
        billing_type: "invoice",
        billed_on: GitHub::Billing.today + 5.months
      org.add_member(create(:user))
      creator = Business::Creator.new(
        organization: org,
        business_params: {
          owners: [@org_admin],
          seats: 1,
          name: "wonderland",
          customer_attributes: {
            billing_email: @billing_email.email,
          }
        },
        actor: @org_admin,
      )
      refute_predicate creator, :valid?
      assert_equal \
        "Not enough seats to add the organization to the enterprise account. " +
        "Please contact sales at #{GitHub.enterprise_web_url}/contact" +
        " to add more seats before proceeding",
        creator.error_message
    end

    test "disallows seats greater than 0 if metered plan" do
      c = Business::Creator.new(
        business_params: {
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          seats: 100,
          customer_attributes: {
            metered_ghe: true,
          },
        },
      )
      refute c.valid?
      assert_equal c.error_message, "Metered plans cannot have seats."
    end

    test "allows seats greater than 0 if metered trial" do
      c = Business::Creator.new(
        require_owners: false,
        business_params: {
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          seats: 100,
          trial_expires_at: 30.days.from_now,
          customer_attributes: {
            metered_ghe: true,
            billing_type: Customer::BILLING_TYPE_INVOICE
          },
        },
      )
      assert c.valid?
    end

    context "for billing email" do
      test "requires a valid email" do
        unverified_email = create(:user_email, user: @org_admin)
        c = Business::Creator.new(
          organization: @org,
          business_params: {
            name: "gibson and sterling, llc",
            billing_email: "notvalid",
            owners: [@org_admin],
            seats: 100,
          },
          actor: @org_admin)
        refute c.valid?
        assert_equal c.error_message, "Billing email does not look like an email address"
      end
    end
  end

  context "saving" do
    test "fails if invalid" do
      c = Business::Creator.new(
        organization: @org,
        business_params: nil,
        actor: @org_admin)
      assert_raises ArgumentError do
        c.save!
      end
    end

    test "can create a new business without an admin" do
      creator = Business::Creator.new(
        business_params: {
          seats: 100,
          name: "wonderland",
          customer_attributes: {
              billing_email: @billing_email.email,
          }
        },
        actor: @org_admin,
        require_owners: false)
      creator.save!
      business = Business.find_by(name: "wonderland")
      assert_empty T.must(business).owners
    end

    test "creates new business without organization" do
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        business_params: {
          owners: owners,
          seats: 100,
          name: "gibson and sterling, llc",
          billing_email: @billing_email.email,
        },
        actor: @org_admin
      )
      c.save!
      business = Business.find_by(name: "gibson and sterling, llc")
      assert owners.all? { |a| T.must(business).owner?(a) }
      assert T.must(business).owner?(@org_admin)
      assert_equal @billing_email.email, T.must(business).billing_email
    end

    test "creates new business with organization" do
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          customer_attributes: {
            billing_type: Customer::BILLING_TYPE_CARD,
          }
        },
        actor: @org_admin
      )
      c.save!
      business = Business.find_by(name: "gibson and sterling, llc")
      assert_equal T.must(T.must(business).customer).billing_type, "card"
      assert_equal T.must(T.must(business).customer).term_length, 12
      assert_equal @org.reload.business, business
      assert_equal @org.billing_email, @billing_email.email
      assert owners.all? { |a| T.must(business).owner?(a) }
      assert T.must(business).owner?(@org_admin)
      assert_equal @billing_email.email, T.must(business).billing_email
      assert_equal @org, T.must(business).upgraded_from
    end

    test "stores the organization's previous plan while upgrading into a business" do
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          customer_attributes: {
            billing_type: Customer::BILLING_TYPE_CARD,
          }
        },
        actor: @org_admin
      )
      c.save!
      business = Business.find_by(name: "gibson and sterling, llc")
      assert_equal @org, T.must(business).upgraded_from
      assert_equal "business_plus", T.must(business).upgraded_from_plan
    end

    test "transfers an enterprise-plan organization's coupon to the business when present", skip_enterprise: true do
      coupon = create(:coupon, discount: "$5")
      @org.redeem_coupon(coupon)

      assert @org.coupon.present?
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          customer_attributes: {
            billing_type: Customer::BILLING_TYPE_CARD,
          }
        },
        actor: @org_admin
      )

      c.save!
      business = Business.find_by(name: "gibson and sterling, llc")
      assert_equal @org.reload.business, business
      refute_predicate @org, :has_an_active_coupon?
      assert_predicate business, :has_an_active_coupon?
      assert_equal coupon, T.must(business).coupon
    end

    test "suspends organization subscription when creating new trial business with organization" do
      plan_subscription = create(:billing_plan_subscription, :zuora, user: @org)
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          customer_attributes: {
            billing_type: Customer::BILLING_TYPE_CARD,
          },
          trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        },
        actor: @org_admin
      )
      assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [@org.plan_subscription]) do  # Ensure plan subscription is suspended
        perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
          c.save!
        end
      end
    end if GitHub.billing_enabled?

    test "enqueues the enterprise cloud trial check job to display the trial banner if organization is present" do
      assert_enqueued_with(job: Billing::EnterpriseCloudTrialCheckJob, args: [@org.id], queue: "billing") do
        owners = [@org_admin, create(:user), create(:user)]
        c = Business::Creator.new(
          organization: @org,
          business_params: {
            owners: owners,
            billing_email: @billing_email.email,
            name: "gibson and sterling, llc",
            customer_attributes: {
              billing_type: Customer::BILLING_TYPE_CARD,
            }
          },
          actor: @org_admin
        )
        c.save!
      end
    end if GitHub.billing_enabled?

    test "does not enqueue the enterprise cloud trial check job when billing is disabled" do
      assert_enqueued_jobs(0, queue: "billing") do
        owners = [@org_admin, create(:user), create(:user)]
        c = Business::Creator.new(
          organization: @org,
          business_params: {
            owners: owners,
            billing_email: @billing_email.email,
            name: "gibson and sterling, llc",
            customer_attributes: {
              billing_type: Customer::BILLING_TYPE_CARD,
            }
          },
          actor: @org_admin
        )
        c.save!
      end
    end if !GitHub.billing_enabled?

    test "accepts customer attributes" do
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: [@org_admin],
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
          customer_attributes: {
            term_length: 67,
            billing_type: Customer::BILLING_TYPE_INVOICE,
          },
        },
        actor: @org_admin
      )
      c.save!

      business = Business.find_by(name: "gibson and sterling, llc")
      assert_equal T.must(T.must(business).customer).billing_type, "invoice"
      assert_equal T.must(T.must(business).customer).term_length, 67
    end

    test "runs BusinessCreatedFromOrganizationJob if business is created with an organization" do
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
        },
        actor: @org_admin
      )
      assert_enqueued_jobs 1, only: BusinessCreatedFromOrganizationJob do
        c.save!
      end
    end

    test "transfers specified settings to enterprise when provided" do
      create :verifiable_domain, owner: @org, domain: "www.github.com", verified: false
      create :verifiable_domain, owner: @org, domain: "sub.github.com", verified: true
      @org.enable_notification_restrictions(actor: @org_admin, notify_members: false)
      assert_predicate @org, :restrict_notifications_to_verified_domains?

      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
        },
        actor: @org_admin,
        settings_to_transfer: [
          { name: :domains, description: "Verified and approved domains configuration" },
        ]
      )

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        c.save!
      end

      assert business = @org.reload.business
      assert_equal 2, business.verifiable_domains.count
      assert_predicate business, :restrict_notifications_to_verified_domains?
      assert_predicate @org.reload, :restrict_notifications_to_verified_domains?
      assert_predicate @org, :restrict_notifications_to_verified_domains_policy?
    end

    test "does not transfer settings to enterprise when not provided" do
      create :verifiable_domain, owner: @org, domain: "www.github.com", verified: false
      create :verifiable_domain, owner: @org, domain: "sub.github.com", verified: true
      @org.enable_notification_restrictions(actor: @org_admin, notify_members: false)
      assert_predicate @org, :restrict_notifications_to_verified_domains?

      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
        },
        actor: @org_admin,
        settings_to_transfer: []
      )

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        c.save!
      end

      assert business = @org.reload.business
      assert_equal 0, business.verifiable_domains.count
      refute_predicate business, :restrict_notifications_to_verified_domains?
      assert_predicate @org.reload, :restrict_notifications_to_verified_domains?
      refute_predicate @org, :restrict_notifications_to_verified_domains_policy?
    end

    test "waits for replication lag" do
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        business_params: {
          owners: owners,
          seats: 100,
          name: "gibson and sterling, llc",
          billing_email: @billing_email.email,
        },
        actor: @org_admin
      )
      WaitForReplication.any_instance.expects(:wait!).at_least_once.returns(nil)
      c.save!
      business = Business.find_by(name: "gibson and sterling, llc")
      refute_nil business
    end

    test "instruments create_trial when an enterprise trial is created" do
      GitHub.flipper[:salesforce_trial_event].enable
      Timecop.freeze("2023-04-01") do
        owners = [@org_admin, create(:user), create(:user)]
        c = Business::Creator.new(
          business_params: {
            owners: owners,
            billing_email: @billing_email.email,
            name: "gibson and sterling, llc",
            seats: 100,
            trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now,
          },
          actor: @org_admin
        )
        c.save!

        business = Business.find_by!(name: "gibson and sterling, llc")

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          upgraded_organization: nil,
          emu: false,
          metered: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          metered: false,
          emu: false,
          billing_email: business.billing_email,
          enterprise_name: "gibson and sterling, llc",
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "instruments metered classic trial" do
      GitHub.flipper[:salesforce_trial_event].enable
      Timecop.freeze("2023-04-01") do
        owners = [@org_admin, create(:user), create(:user)]
        c = Business::Creator.new(
          business_params: {
            owners: owners,
            billing_email: @billing_email.email,
            name: "gibson and sterling, llc",
            seats: 100,
            trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now,
            customer_attributes: {
              billing_type: Customer::BILLING_TYPE_CARD,
              metered_ghe: true,
            }
          },
          actor: @org_admin
        )
        c.save!

        business = Business.find_by!(name: "gibson and sterling, llc")

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          upgraded_organization: nil,
          emu: false,
          metered: true,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          upgraded_organization: nil,
          emu: false,
          metered: true,
          billing_email: business.billing_email,
          enterprise_name: "gibson and sterling, llc",
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "instruments metered emu trial" do
      GitHub.flipper[:salesforce_trial_event].enable
      Timecop.freeze("2023-04-01") do
        owners = []
        c = Business::Creator.new(
          business_params: {
            can_self_serve: true,
            owners: owners,
            business_type: "enterprise_managed",
            billing_email: @billing_email.email,
            shortcode: "gib",
            name: "gibson and sterling, llc",
            seats: 100,
            trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now,
            customer_attributes: {
              billing_type: Customer::BILLING_TYPE_CARD,
              metered_ghe: true,
            }
          },
          actor: @org_admin,
          require_owners: false
        )
        c.save!

        business = Business.find_by!(name: "gibson and sterling, llc")

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          upgraded_organization: nil,
          emu: true,
          metered: true,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: T.must(business).trial_expires_at,
          upgraded_organization: nil,
          emu: true,
          metered: true,
          billing_email: business.billing_email,
          enterprise_name: "gibson and sterling, llc",
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "instruments create_trial when an enterprise trial is created from upgrading an organization" do
      GitHub.flipper[:salesforce_trial_event].enable
      Timecop.freeze("2023-04-01") do
        owners = [@org_admin, create(:user), create(:user)]
        c = Business::Creator.new(
          organization: @org,
          business_params: {
            owners: owners,
            billing_email: @billing_email.email,
            name: "gibson and sterling, llc",
            trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now,
          },
          actor: @org_admin
        )
        c.save!

        assert business = @org.reload.business

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: business.trial_expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(@org),
          emu: false,
          metered: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@org_admin),
          user_initiated: :USER,
          status: :CREATED,
          expiration_timestamp: T.must(business).trial_expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(@org),
          emu: false,
          metered: false,
          billing_email: business.billing_email,
          enterprise_name: "gibson and sterling, llc",
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "instruments adding an organization with organization_upgrade true when business created with an org" do
      events = subscribe "business.add_organization"
      owners = [@org_admin, create(:user), create(:user)]
      c = Business::Creator.new(
        organization: @org,
        business_params: {
          owners: owners,
          billing_email: @billing_email.email,
          name: "gibson and sterling, llc",
        },
        actor: @org_admin
      )
      c.save!
      assert business = @org.reload.business

      expected_payload = {
        business_id: business.id,
        business: business.slug,
        name: business.name,
        org: @org.login,
        org_id: @org.id,
        organization_upgrade: true
      }

      assert event = events.pop, "business.add_organization event was expected"
      assert events.empty?
      assert_equal expected_payload, event.payload
    end

    if !GitHub.single_business_environment?
      test "instruments upon Business creation if business is a trial" do
        events = assert_performed_audit_entries(count: 1, only: "business.create_trial") do
          @business = Business::Creator.new(
            business_params: {
              name: "DEF Ltd",
              owners: [@org_admin, create(:user), create(:user)],
              seats: 20,
              trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
            }
          ).save!
        end
        assert_equal 1, GitHub.dogstats.increments("business.trial.create").length
      end

      test "does not instrument upon Business creation if business is not a trial" do
        events = assert_performed_audit_entries(count: 0, only: "business.create_trial") do
          @business = Business::Creator.new(
            business_params: {
              name: "DEF Ltd",
              owners: [@org_admin, create(:user), create(:user)],
              seats: 20
            }
          ).save!
        end
      end
    end
  end
end
