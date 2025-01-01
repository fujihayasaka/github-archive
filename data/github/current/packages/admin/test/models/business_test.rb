# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper
  include StringFromBinaryTestHelper
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include TurboghasHelpers
  include AuthenticationHelpers::SAML
  include ApiProgrammaticGrantHelpers
  include FineGrainedPermissionsTestHelper

  fixtures do
    @owner = create(:user, login: "admin-user")
    @user = create(:user, login: "user")
    @member1 = create(:user, :verified, login: "member1")
    @member2 = create(:user, login: "member2")
    @public_member_of_org2 = create(:user, login: "public-member2")
    @forker = create(:user, login: "forker")
    @collaborator = create(:user, login: "collaborator")
    @collaborator2 = create(:user, login: "collaborator2")
    @suspended = create(:suspended_user, login: "suspended-user")
    @billing_manager = create(:user, login: "billing-manager")

    @org1 = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
    @org1.allow_private_repository_forking(actor: @org1.admins.first)
    @org1.add_member(@member1)
    @repo1 = create :repository, :minimal, owner: @org1
    RepositoryInvitation.invite_to_repo_without_confirmation(@collaborator, @org1.admins.first, @repo1)

    @org2 = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
    @org2.add_member(@member2)
    @org2.add_member(@public_member_of_org2)
    @org2.publicize_member(@public_member_of_org2)
    @repo2 = create :repository, :minimal, owner: @org2
    RepositoryInvitation.invite_to_repo_without_confirmation(@collaborator2, @org2.admins.first, @repo2)

    only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
    @business = perform_enqueued_jobs only: only do
      create :business, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2], seats: 20
    end
    @business.customer.update!(billed_via_billing_platform: true)
    @business.billing.add_manager(@billing_manager, actor: @owner)

    unless GitHub.single_business_environment?
      @deletable_business = create :business, owners: [@owner]
      @enterprise_managed_business = \
        create :business, business_type: :enterprise_managed, shortcode: "qqq"
      @another_business = create :business, name: "ANO Ltd"

      @upgrading_org = create :organization, name: "upgrading-org", plan: "business", admins: [@owner]
      @upgrading_business = perform_enqueued_jobs only: only do
        create :business, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: @upgrading_org.id
      end
      @upgrading_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
      @upgrading_org.upgrade_to_enterprise_in_progress!(@upgrading_business)

      Timecop.freeze(10.minutes.ago) do
        @soft_deleted_org = create(
          :organization, admins: [@owner], login: "soft-deleted-org",
          business: @business
        )
        @soft_deleted_org.soft_delete!
      end
    end

    @integration = create :enterprise_owned_integration, owner: @business
    @integration_installation = make_integration_installation(target: @business, integration: @integration, permissions: { Business::Resources.subject_types.first => :read })

    @business_user_account = create(:business_user_account,
                                    business: @business,
                                    user: nil)
    @enterprise_installation = create(:enterprise_installation, owner: @business)
    @enterprise_installation_user_account = create(:enterprise_installation_user_account,
                                                   enterprise_installation: @enterprise_installation,
                                                   business_user_account: @business_user_account)
    create(:enterprise_installation_user_account_email,
           enterprise_installation_user_account: @enterprise_installation_user_account,
           primary: true)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  teardown do
    disable_feature_flag(:ghec_receive_welcome_enterprise_trial_upgrade_account_email)
    disable_feature_flag(:ghec_receive_net_new_enterprise_account_email)
  end

  context "set shortcode" do
    test "uses passed in shortcode and does not set random shortcode" do
      business = Business.create(name: "test", slug: "test", shortcode: "test", business_type: :enterprise_managed, seats: 1)
      refute_nil business.shortcode
      assert_equal "test", business.shortcode
    end

    test "fails to create a business when shortcode is not passed in and does not set random shortcode" do
      business = Business.create(name: "test", slug: "test", business_type: :enterprise_managed, seats: 1)
      assert_includes business.errors.messages[:shortcode], "required to enable enterprise managed users"
    end
  end

  context "validations" do
    test "require that slug is present" do
      business = build :business, name: "Valid name", slug: ""
      refute_predicate business, :valid?
      assert_includes business.errors[:slug], "can't be blank"
      refute_includes business.errors[:slug], "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    test "require that slug is of the correct length" do
      business = build :business, name: "Valid name", slug: "e" * 100
      refute_predicate business, :valid?
      assert_includes business.errors[:slug], "is too long (maximum is 60 characters)"
    end

    test "require that slug is of a valid format" do
      business = build :business, name: "Valid name", slug: "I AM NOT A SLUG"
      refute_predicate business, :valid?
      assert_includes business.errors[:slug], "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    test "reject slug containing emojis" do
      business = build :business, name: "a name", slug: "🐹"

      refute_predicate business, :valid?
      assert_includes business.errors[:slug], "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    unless GitHub.single_business_environment?
      test "require that slug is unique" do
        business = build :business, name: "Valid name", slug: "cde-ltd"
        refute_predicate business, :valid?
        assert_includes business.errors[:slug], "is already taken by another enterprise account"
      end

      test "require that slug is case-insensitively unique" do
        business = build :business, name: "Valid name", slug: "CDE-LTD"
        refute_predicate business, :valid?
        assert_includes business.errors[:slug], "is already taken by another enterprise account"
      end
    end

    test "require that name is present" do
      business = build :business, name: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:name], "can't be blank"
    end

    test "require that name be no longer than 60 characters" do
      long_name = "Z" * 61
      business = build :business, name: long_name

      refute_predicate business, :valid?
      assert_includes business.errors[:name], "is too long (maximum is 60 characters)"
    end

    test "require that terms_of_service_company_name be no longer than 60 characters" do
      long_name = "Z" * 61
      business = build :business, name: "Hello", terms_of_service_company_name: long_name

      refute_predicate business, :valid?
      assert_includes business.errors[:terms_of_service_company_name], "is too long (maximum is 60 characters)"
    end

    test "require that seats is present" do
      business = build :business, seats: nil

      refute_predicate business, :valid?
      assert_includes business.errors[:seats], "can't be blank"
    end

    test "require that seats is a number" do
      business = build :business, seats: "mona"

      refute_predicate business, :valid?
      assert_includes business.errors[:seats], "is not a number"
    end

    test "require that billing end date is present if the business is invoiced" do
      business = build :business

      business.customer.billing_type = "invoice"
      business.customer.billing_end_date = nil

      assert_predicate business, :invoiced?
      refute_predicate business, :valid?
      assert_includes \
        business.errors[:"customer.billing_end_date"],
        "must be specified for invoiced customers"
    end if GitHub.billing_enabled?

    test "require that billing end date is within the accepted range if present" do
      business = build :business

      business.customer.billing_type = "invoice"
      business.customer.billing_end_date = 10_000_000.years.from_now

      refute_predicate business, :valid?
      assert_equal \
        ["is not within the supported date range"],
        business.errors[:"customer.billing_end_date"]
    end

    if GitHub.single_business_environment?
      test "don't require billing_term_ends_at in single business environment" do
        GitHub.global_business.customer.update(billing_end_date: nil)
        assert_predicate GitHub.global_business, :valid?
      end
    end

    test "does not require billing term date to be present if the business is not invoiced" do
      business = build :business, billing_term_ends_at: nil
      business.customer.billing_type = nil
      business.customer.billing_end_date = nil

      assert_predicate business, :valid?
    end

    test "only allows users as admins" do
      business = build :business, owners: [create(:team)]

      refute_predicate business, :valid?
      assert_includes business.errors[:owners], "must all be users"
    end

    test "validates terms_of_service_type" do
      business = build :business, terms_of_service_type: "Whatevs"
      refute_predicate business, :valid?
      assert_includes business.errors[:terms_of_service_type], "Whatevs is not a valid terms of service type"
    end

    test "validates billing email when present" do
      business = build :business, billing_email: "notarealemail"
      refute_predicate business, :valid?
      assert_includes business.errors[:billing_email], "does not look like an email address"
    end

    test "validates billing email is not disposable when present", skip_enterprise: true do
      email = "billing@gmai.com"
      assert UserEmail::DisposableEmailsDependency.disposable_email?(email)

      business = build :business, billing_email: email

      refute_predicate business, :valid?
      assert_includes \
        business.errors[:billing_email],
        "cannot be billing@gmai.com - domain could not be verified"
    end

    test "can optionally skip disposable billing email validation", skip_enterprise: true do
      email = "billing@gmai.com"
      assert UserEmail::DisposableEmailsDependency.disposable_email?(email)

      @business.skip_billing_email_not_disposable_validation = true
      @business.update! billing_email: email

      assert_predicate @business, :valid?
    end

    test "does not validate billing email when nil" do
      business = build :business, billing_email: nil
      assert_predicate business, :valid?
    end

    test "require that terms_of_service_notes is no longer than specified length" do
      long_notes = "x" * (Business::MAX_TERMS_OF_SERVICE_NOTES_LENGTH + 1)
      business = build :business, terms_of_service_notes: long_notes

      refute_predicate business, :valid?
      assert_includes business.errors[:terms_of_service_notes], "is too long (maximum is 255 characters)"
    end

    test "require that website_url is no longer than specified length" do
      long_url = "Z" * (Business::MAX_WEBSITE_URL_LENGTH + 1)
      business = build :business, website_url: long_url

      refute_predicate business, :valid?
      assert_includes business.errors[:website_url], "is too long (maximum is 255 characters)"
    end

    test "require that website_url is a valid http(s) URL" do
      @business.website_url = "check out my website"
      refute_predicate @business, :valid?
      assert_includes @business.errors[:website_url], "is not a valid http(s) URL"

      @business.website_url = "foo|.com/baz"
      refute_predicate @business, :valid?
      assert_includes @business.errors[:website_url], "is not a valid http(s) URL"

      @business.website_url = "ftp://example.com/hello"
      refute_predicate @business, :valid?
      assert_includes @business.errors[:website_url], "is not a valid http(s) URL"

      @business.website_url = ""
      assert_predicate @business, :valid?

      @business.website_url = "example.com/hello"
      assert_predicate @business, :valid?

      @business.website_url = "http://example.com/hello"
      assert_predicate @business, :valid?

      @business.website_url = "https://example.com/hello"
      assert_predicate @business, :valid?
    end

    test "require that location is no longer than specified maximum" do
      long_location = "Z" * (Business::MAX_LOCATION_LENGTH + 1)
      business = build :business, location: long_location

      refute_predicate business, :valid?
      assert_includes business.errors[:location], "is too long (maximum is 255 characters)"
    end

    test "requires that description is no longer than specified maximum" do
      too_long = "Z" * (Business::MAX_DESCRIPTION_LENGTH + 1)
      business = build :business, description: too_long

      refute_predicate business, :valid?
      assert_includes business.errors[:description], "is too long (maximum is 160 characters)"
    end

    test "requires that long_description is no longer than specified maximum" do
      too_long = "Z" * (Business::MAX_LONG_DESCRIPTION_LENGTH + 1)
      business = build :business, long_description: too_long

      refute_predicate business, :valid?
      assert_includes business.errors[:long_description], "is too long (maximum is 125000 characters)"
    end

    test "require that industry is present for DFD business" do
      business = build :business, new_dfd_trial: true, industry: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:industry], "must be selected"
    end

    test "require that employees size is present for DFD business" do
      business = build :business, new_dfd_trial: true, employees_size: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:employees_size], "must be selected"
    end

    test "require that country code is present for DFD business" do
      business = build :business, new_dfd_trial: true, country_code: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:country_code], "must be selected"
    end

    test "require that EMU IDP is present for DFD enterprise managed business" do
      business = build :business, new_dfd_trial: true, business_type: :enterprise_managed, emu_idp: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:emu_idp], "must be selected"
    end

    test "require that billing full name is present for DFD business" do
      business = build :business, new_dfd_trial: true, billing_full_name: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:billing_full_name], "can't be blank"
    end

    test "require that billing email is present for DFD business" do
      business = build :business, new_dfd_trial: true, billing_email: ""

      refute_predicate business, :valid?
      assert_includes business.errors[:billing_email], "can't be blank"
    end

    unless GitHub.single_business_environment?
      test "requires that there are enough seats to cover existing members" do
        assert_equal 6, @business.total_consumed_licenses
        create(:enterprise_agreement, seats: 4, business: @business)

        @business.seats = 1
        refute_predicate @business, :valid?
        assert_includes @business.errors[:seats], "must be equal to or greater than 2. The total consumed licenses (both GHE and VSS), which is currently 6, cannot be more than the total purchased licenses (both GHE and VSS), which is currently 5"

        @business.seats = 2
        assert_predicate @business, :valid?

        @business.seats = 3
        assert_predicate @business, :valid?
      end

      test "requires enough seats to cover existing members, accounting for overallocated VSS licenses" do
        assert_equal 6, @business.total_consumed_licenses
        create(:enterprise_agreement, seats: 1, business: @business)
        create_list(:licensing_bundled_license_assignment, 2, business: @business)

        @business.seats = 1

        refute_predicate @business, :valid?
        assert_includes @business.errors[:seats], "must be equal to or greater than 4. The total consumed licenses (both GHE and VSS), which is currently 6, cannot be more than the total purchased licenses (both GHE and VSS), which is currently 3"
      end

      test "includes volume license count" do
        assert_equal 6, @business.consumed_invitable_licenses
        create(:enterprise_agreement, seats: 6, business: @business)
        @business.reload

        @business.seats = 1

        assert_predicate @business, :valid?
      end

      test "does not require business on a metered plan to have enough seats to cover existing members" do
        @business.customer.update(metered_ghe: true)

        assert_equal 6, @business.total_consumed_licenses

        @business.seats = 0

        assert_predicate @business, :valid?
      end
    end

    if GitHub.single_business_environment?
      test "does not allow additional businesses to be created in a single global business environment" do
        Business.destroy_all
        create :business
        assert_raises Business::SingleGlobalBusinessError do
          create :business
        end
      end
    else
      test "allows multiple businesses to be created when not in a single global business environment" do
        Business.destroy_all
        2.times { create :business }
      end
    end

    unless GitHub.single_business_environment?
      test "require that enterprise_web_business_id is numeric" do
        business = build :business, name: "Valid name", enterprise_web_business_id: "blah"
        refute_predicate business, :valid?
        assert_includes business.errors[:enterprise_web_business_id], "is not a number"
      end

      test "require that enterprise_web_business_id is positive" do
        business = build :business, name: "Valid name", enterprise_web_business_id: -1337
        refute_predicate business, :valid?
        assert_includes business.errors[:enterprise_web_business_id], "must be greater than 0"
      end

      test "require that enterprise_web_business_id is unique" do
        @business.update! enterprise_web_business_id: 1337
        business = build :business, name: "Valid name", enterprise_web_business_id: 1337
        refute_predicate business, :valid?
        assert_includes business.errors[:enterprise_web_business_id], "is already taken by another enterprise account"
      end

      test "allows blank enterprise_web_business_id" do
        business = build :business, enterprise_web_business_id: nil
        assert_predicate business, :valid?
        assert_empty business.errors[:enterprise_web_business_id]

        business.enterprise_web_business_id = ""

        assert_predicate business, :valid?
        assert_empty business.errors[:enterprise_web_business_id]
      end
    end

    unless GitHub.single_business_environment?
      test "accepts a valid business type" do
        business = build :business, business_type: "enterprise_managed", shortcode: "abc"
        assert_predicate business, :valid?
        assert_empty business.errors[:business_type]

        business.business_type = "default_managed"
        business.shortcode = nil
        assert_predicate business, :valid?
        assert_empty business.errors[:business_type]
        assert_raises(ArgumentError) do
          business.business_type = "other"
        end
      end

      test "require shortcode when business type is enterprise_managed" do
        business = build :business, business_type: :enterprise_managed
        refute_predicate business, :valid?
        assert_includes business.errors[:shortcode], "required to enable enterprise managed users"
      end

      test "does not allow shortcode when business type is default" do
        business = build :business, shortcode: "abc"
        refute_predicate business, :valid?
        assert_includes business.errors[:shortcode], "only allowed when enterprise managed users is enabled"
      end

      test "allows valid shortcode" do
        business = build :business, business_type: :enterprise_managed, shortcode: "abc"
        assert_predicate business, :valid?
        assert_empty business.errors[:shortcode]
      end

      test "allows reserved login shortcode" do
        business = build :business, business_type: :enterprise_managed, shortcode: "discover"
        assert_predicate business, :valid?
        assert_empty business.errors[:shortcode]
      end

      test "require that shortcode be the correct length" do
        short_business = build :business, business_type: :enterprise_managed, shortcode: "ab"
        long_business = build :business, business_type: :enterprise_managed, shortcode: "abcdefghi"
        refute_predicate short_business, :valid?
        refute_predicate long_business, :valid?
        assert_includes short_business.errors[:shortcode], "is too short (minimum is 3 characters)"
        assert_includes long_business.errors[:shortcode], "is too long (maximum is 8 characters)"
      end

      test "require that shortcode be the alphanumeric" do
        business = build :business, business_type: :enterprise_managed, shortcode: "ab-cd"
        refute_predicate business, :valid?
        assert_includes business.errors[:shortcode], "may only contain alphanumeric characters"
      end

      test "require that shortcode be case-insensitively unique" do
        business = build :business, business_type: :enterprise_managed, shortcode: "QQQ"
        refute_predicate business, :valid?
        assert_includes business.errors[:shortcode], "is already taken by another enterprise account"
      end

      test "shortcode can't be changed" do
        @enterprise_managed_business.shortcode = "xyz"
        refute_predicate @enterprise_managed_business, :valid?
        assert_includes @enterprise_managed_business.errors[:shortcode], "can't be changed"
      end

      test "spammy_reason must be unicode3 if present" do
        business = build :business, spammy_reason: "Ate too much 🍿"
        refute_predicate business, :valid?
        assert_includes business.errors[:spammy_reason], "doesn't accept 4-byte Unicode"
      end

      [:name, :terms_of_service_company_name, :description, :long_description].each do |field|
        test "supports emoji for #{field}" do
          @business.update! field => "we ❤️ emojis"

          assert_multibyte_tracked_changes(@business, field)
        end
      end
    end
  end

  context "#seats_plan_type" do
    test "defaults to full" do
      assert @business.seats_plan_full?
      refute @business.seats_plan_basic?
    end

    unless GitHub.single_business_environment?
      test "defaults to full on new business" do
        business = create :business
        assert business.seats_plan_full?
        refute business.seats_plan_basic?
      end

      test "can be set to basic" do
        business = create :business, seats_plan_type: :basic
        refute business.seats_plan_full?
        assert business.seats_plan_basic?
      end
    end
  end

  context "user_on_seat_plan?" do
    test "true for default business" do
      assert @business.user_on_seat_plan?(create(:user))
    end

    unless GitHub.single_business_environment?
      test "true when seats_plan_type is full" do
        business = create :business
        assert business.user_on_seat_plan?(create(:user))
      end

      test "false when seats_plan_type is basic" do
        business = create :business, seats_plan_type: :basic
        refute business.user_on_seat_plan?(create(:user))
      end
    end
  end

  context "#can_transition_to_seats_plan_type?" do
    test "false when attempting to transition to invalid plan" do
      refute @business.can_transition_to_seats_plan_type?(:invalid)
      refute_nil @business.can_transition_to_seats_plan_type_issues(:invalid)[:invalid_plan]
      refute_nil @business.can_transition_to_seats_plan_type_issues(:invalid)[:invalid_plan][:message]
    end

    test "false when attempting to transition from full to full" do
      refute @business.can_transition_to_seats_plan_type?(:full)
      refute_nil @business.can_transition_to_seats_plan_type_issues(:full)[:current_plan]
      refute_nil @business.can_transition_to_seats_plan_type_issues(:full)[:current_plan][:message]
    end

    unless GitHub.single_business_environment?
      test "false when attempting to transition from basic to basic" do
        business = create :business, seats_plan_type: :basic
        refute business.can_transition_to_seats_plan_type?(:basic)
        refute_nil business.can_transition_to_seats_plan_type_issues(:basic)[:current_plan]
        refute_nil business.can_transition_to_seats_plan_type_issues(:basic)[:current_plan][:message]
      end

      test "true when attempting to transition from basic to full" do
        business = create :business, seats_plan_type: :basic
        assert business.can_transition_to_seats_plan_type?(:full)
        assert_equal [], business.can_transition_to_seats_plan_type_issues(:full).keys
      end

      test "true when attempting to transition from full to basic with no organizations" do
        business = create :business, seats_plan_type: :full
        assert business.can_transition_to_seats_plan_type?(:basic)
        assert_equal [], business.can_transition_to_seats_plan_type_issues(:basic).keys
      end

      test "true when attempting to transition from full to basic with soft-deleted organizations" do
        org = create :organization, admins: [@owner]
        business = create :business, organizations: [org], seats_plan_type: :full
        org.soft_delete!(@owner)
        assert business.can_transition_to_seats_plan_type?(:basic)
        assert_equal [], business.can_transition_to_seats_plan_type_issues(:basic).keys
      end

      test "false when attempting to transition from full to basic with organizations" do
        org = create :organization
        business = create :business, organizations: [org], seats_plan_type: :full
        refute business.can_transition_to_seats_plan_type?(:basic)
        refute_nil business.can_transition_to_seats_plan_type_issues(:basic)[:organizations_present]
        refute_nil business.can_transition_to_seats_plan_type_issues(:basic)[:organizations_present][:message]
        assert_equal [org.id], business.can_transition_to_seats_plan_type_issues(:basic)[:organizations_present][:organization_ids]
      end

      test "can_transition_to_seats_plan_type_issues returns multiple issues" do
        org = create :organization
        business = create :business, organizations: [org], seats_plan_type: :full
        refute business.can_transition_to_seats_plan_type?(:invalid)
        refute_nil business.can_transition_to_seats_plan_type_issues(:invalid)[:invalid_plan]
        refute_nil business.can_transition_to_seats_plan_type_issues(:invalid)[:organizations_present]
        assert_equal [org.id], business.can_transition_to_seats_plan_type_issues(:invalid)[:organizations_present][:organization_ids]
      end
    end
  end

  context "#reason_unable_to_transition_to_seats_plan_type", skip_enterprise: true do
    test "returns an empty string when transition to seats plan type permitted" do
      business = create :business, seats_plan_type: :basic

      assert business.can_transition_to_seats_plan_type?(:full)
      assert_empty business.reason_unable_to_transition_to_seats_plan_type(:full)
    end

    test "returns reason when attempting to transition from full to basic with organizations" do
      org = create :organization
      business = create :business, organizations: [org], seats_plan_type: :full

      refute business.can_transition_to_seats_plan_type?(:basic)

      reason = business.reason_unable_to_transition_to_seats_plan_type(:basic)

      assert_equal "There are existing organizations that must be removed.", reason
    end

    test "returns reason when attempting to transition has multiple issues" do
      org = create :organization
      business = create :business, organizations: [org], seats_plan_type: :full

      refute business.can_transition_to_seats_plan_type?(:invalid)
      refute_nil business.can_transition_to_seats_plan_type_issues(:invalid)[:invalid_plan]
      refute_nil business.can_transition_to_seats_plan_type_issues(:invalid)[:organizations_present]

      reason = business.reason_unable_to_transition_to_seats_plan_type(:invalid)

      assert_equal \
        "The seats plan type is invalid. Only full and basic can be selected. There are existing organizations that must be removed.",
        reason
    end
  end

  context "#transition_to_seats_plan_type", skip_enterprise: true do
    test "returns false when transition not permitted" do
      org = create :organization
      business = create :business, organizations: [org], seats_plan_type: :full

      assert_predicate business, :seats_plan_full?
      refute business.can_transition_to_seats_plan_type?(:basic)

      refute business.transition_to_seats_plan_type(:basic)
      assert_predicate business, :seats_plan_full?
    end

    test "returns true when transition permitted and seats plan type is changed" do
      business = create :business, seats_plan_type: :full

      assert_predicate business, :seats_plan_full?
      assert business.can_transition_to_seats_plan_type?(:basic)

      assert business.transition_to_seats_plan_type(:basic)
      assert_predicate business, :seats_plan_basic?
    end

    test "enables support for unaffiliated user accounts when changing from basic to full" do
      business = create :business, seats_plan_type: :basic
      assert_predicate business, :supports_unaffiliated_user_accounts?
      assert business.can_transition_to_seats_plan_type?(:full)

      assert business.transition_to_seats_plan_type(:full)

      assert_predicate business, :seats_plan_full?
      assert_predicate business, :supports_unaffiliated_user_accounts?
    end

    test "enables copilot_metered_enterprise feature flag when changing from basic to full when metered" do
      business = create :business, seats_plan_type: :basic
      business.customer.update! metered_ghe: true
      assert_predicate business.reload, :supports_unaffiliated_user_accounts?
      assert business.can_transition_to_seats_plan_type?(:full)
      assert_predicate business, :metered_ghe?

      assert business.transition_to_seats_plan_type(:full)

      assert_predicate business, :seats_plan_full?
      assert_predicate business, :supports_unaffiliated_user_accounts?
      assert business.feature_enabled?(:copilot_metered_enterprise)
    end

    test "doesn't enable copilot_metered_enterprise feature flag when changing from basic to full when not metered" do
      business = create :business, seats_plan_type: :basic
      # Disable feature for all features test mode
      disable_feature_flag(:copilot_metered_enterprise, business)
      assert_predicate business, :supports_unaffiliated_user_accounts?
      assert business.can_transition_to_seats_plan_type?(:full)
      refute_predicate business, :metered_ghe?

      assert business.transition_to_seats_plan_type(:full)

      assert_predicate business, :seats_plan_full?
      assert_predicate business, :supports_unaffiliated_user_accounts?
      refute business.feature_enabled?(:copilot_metered_enterprise)
    end

    test "maintains Copilot settings when changing from basic to full when metered" do
      business = create :business, seats_plan_type: :basic
      business.customer.update! metered_ghe: true
      assert_predicate business.reload, :supports_unaffiliated_user_accounts?
      assert business.can_transition_to_seats_plan_type?(:full)
      assert_predicate business, :metered_ghe?
      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot!
      assert_predicate copilot_business, :copilot_enabled?

      assert business.transition_to_seats_plan_type(:full)

      assert_predicate business, :seats_plan_full?
      assert_predicate business, :supports_unaffiliated_user_accounts?
      copilot_business = Copilot::Business.new(business)
      assert_predicate copilot_business, :copilot_enabled?
    end

    test "reduces seats to 0 when changing from full to basic" do
      business = create :business, seats_plan_type: :full, seats: 100

      assert_predicate business, :seats_plan_full?
      assert business.can_transition_to_seats_plan_type?(:basic)

      assert business.transition_to_seats_plan_type(:basic)
      assert_predicate business, :seats_plan_basic?
      assert_equal 0, business.seats
    end

    test "updates license usage after plan change" do
      business = create :business, seats_plan_type: :full

      assert_predicate business, :seats_plan_full?
      assert business.can_transition_to_seats_plan_type?(:basic)

      assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob do
        assert business.transition_to_seats_plan_type(:basic)
      end
      assert_predicate business, :seats_plan_basic?
    end

    test "instruments business.change_seats_plan_type audit log event" do
      business = create :business, seats_plan_type: :full
      assert_predicate business, :seats_plan_full?
      assert business.can_transition_to_seats_plan_type?(:basic)

      events = assert_performed_audit_entries(count: 1, only: "business.change_seats_plan_type") do
        assert business.transition_to_seats_plan_type(:basic)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        business_id: business.id,
        business: business.slug,
        name: business.name,
        seats_plan_type_was: "full",
        seats_plan_type: "basic",
      }
      assert_subset_hash expected_payload, events.first

      assert_predicate business, :seats_plan_basic?
    end
  end

  context "default_scope" do
    test "excludes businesses with deleted_at set" do
      assert_includes Business.all, @business
      @business.touch :deleted_at
      refute_includes Business.all, @business
    end
  end

  unless GitHub.single_business_environment?
    context "including_deleted scope" do
      test "only returns both active and soft-deleted businesses" do
        @business.touch :deleted_at
        assert_predicate @business, :deleted?
        refute_predicate @another_business, :deleted?
        assert_includes Business.including_deleted, @business
        assert_includes Business.including_deleted, @another_business
      end
    end

    context "deleted scope" do
      test "only returns businesses with deleted_at set" do
        @business.touch :deleted_at
        assert_predicate @business, :deleted?
        refute_predicate @another_business, :deleted?
        assert_includes Business.deleted, @business
        refute_includes Business.deleted, @another_business
      end
    end

    context "purgeable scope" do
      test "only returns businesses with deleted_at value earlier than restorable period ago" do
        refute_includes Business.purgeable, @business

        @business.touch :deleted_at
        refute_includes Business.purgeable, @business

        # Marked deleted more than "restorable period" ago
        @business.update! deleted_at: (Business::RESTORABLE_PERIOD + 2.days).ago
        assert_includes Business.purgeable, @business
      end
    end
  end

  if GitHub.billing_enabled?
    context "upgraded_and_not_reviewed scope" do
      test "only includes Businesses upgraded from invoiced orgs that have not been reviewed" do
        assert_empty Business.upgraded_and_not_reviewed

        upgraded_org = create :organization, plan: GitHub::Plan.business
        @business.update! \
          upgraded_at: 2.days.ago,
          upgraded_from: upgraded_org,
          upgraded_from_plan: upgraded_org.plan.name

        free_org = create :organization, plan: GitHub::Plan.free
        upgraded_from_free_org = create :business, \
          name: "Upgraded from a free org",
          upgraded_at: 2.days.ago,
          upgraded_from: free_org,
          upgraded_from_plan: free_org.plan.name

        card_upgraded_org = create :organization, plan: GitHub::Plan.business
        another_business_upgraded_from_org = create :business, \
          name: "Upgraded from a card org",
          upgraded_at: 2.days.ago,
          upgraded_from: card_upgraded_org,
          upgraded_from_plan: card_upgraded_org.plan.name
        another_business_upgraded_from_org.customer.update billing_type: Customer::BILLING_TYPE_CARD

        another_upgraded_org = create :organization, plan: GitHub::Plan.business
        another_business_upgraded_from_org = create :business, \
          name: "Another upgraded from an org",
          upgraded_at: 2.days.ago,
          upgraded_from: another_upgraded_org,
          upgraded_from_plan: another_upgraded_org.plan.name
        another_business_upgraded_from_org.touch :upgrade_reviewed_at

        assert_same_elements [@business], Business.upgraded_and_not_reviewed
      end
    end

    context "self_serve_organization_upgrading_or_upgraded scope" do
      test "includes business upgraded from a team org" do
        team_org = create :organization, plan: GitHub::Plan.business
        business_upgraded_from_teams_org = create :business, \
          :with_self_serve_payment,
          name: "Upgraded from a free org",
          upgraded_at: 2.days.ago,
          upgraded_from: team_org,
          upgraded_from_plan: team_org.plan.name

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgraded_from_teams_org
      end

      test "includes business upgraded from a free org" do
        free_org = create :organization, plan: GitHub::Plan.free
        business_upgraded_from_free_org = create :business, \
          :with_self_serve_payment,
          name: "Upgraded from a free org",
          upgraded_at: 2.days.ago,
          upgraded_from: free_org,
          upgraded_from_plan: free_org.plan.name

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgraded_from_free_org
      end

      test "includes business upgraded from a business_plus org" do
        business_plus = create :organization, plan: GitHub::Plan.business_plus
        business_upgraded_from_business_plus_org = create :business, \
          :with_self_serve_payment,
          name: "Upgraded from a business plus org",
          upgraded_at: 2.days.ago,
          upgraded_from: business_plus,
          upgraded_from_plan: business_plus.plan.name
        business_upgraded_from_business_plus_org.organization_direct_upgraded!

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgraded_from_business_plus_org
      end

      test "includes business that has initiated an upgrade" do
        initiated_upgrade_org = create :organization, plan: GitHub::Plan.free
        business_upgrade_initiated = create :business, \
          :with_self_serve_payment,
          owners: [@owner],
          name: "Upgrade initiated"
        business_upgrade_initiated.initiate_organization_upgrade(@owner)

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgrade_initiated
      end

      test "includes business with upgrade payment in progress" do
        upgrade_in_progress_org = create :organization, plan: GitHub::Plan.free
        business_upgrade_in_progress = create :business, \
          :with_self_serve_payment,
          owners: [@owner],
          name: "Upgrade in progress"
        business_upgrade_in_progress.initiate_organization_upgrade(@owner)
        business_upgrade_in_progress.initiate_organization_upgrade_purchase(@owner)

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgrade_in_progress
      end

      test "does not include business upgraded from an invoiced org" do
        invoiced_upgraded_org = create :organization, plan: GitHub::Plan.business
        business_upgraded_from_invoiced_org = create :business, \
          name: "Upgraded from a card org",
          upgraded_at: 2.days.ago,
          upgraded_from: invoiced_upgraded_org,
          upgraded_from_plan: invoiced_upgraded_org.plan.name
        business_upgraded_from_invoiced_org.customer.update(billing_type: Customer::BILLING_TYPE_INVOICE)

        refute_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, business_upgraded_from_invoiced_org
      end

      test "does not include business upgraded from a trial org" do
        free_org = create :organization, plan: GitHub::Plan.free
        trial_business = create :business, \
          :with_self_serve_payment,
          name: "Upgraded org to trial",
          upgraded_at: 2.days.ago,
          upgraded_from: free_org,
          upgraded_from_plan: free_org.plan.name
        trial_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        refute_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, trial_business
      end

      test "does not include business converted from a trial org" do
        free_org = create :organization, plan: GitHub::Plan.free
        converted_trial_business = create :business, \
          :with_self_serve_payment,
          name: "Upgraded org to converted trial",
          upgraded_at: 2.days.ago,
          upgraded_from: free_org,
          upgraded_from_plan: free_org.plan.name
        converted_trial_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        converted_trial_business.convert_trial

        refute_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, converted_trial_business
      end

      test "includes an upgraded business that was deleted" do
        deleted_upgrade = create :business, \
          :with_self_serve_payment,
          name: "Deleted business",
          deleted_at: 1.day.ago,
          upgraded_at: 5.days.ago

        assert_includes Business.including_deleted.self_serve_organization_upgrading_or_upgraded, deleted_upgrade
      end
    end

    context "auto_pay_rbi_disabled scope" do
      test "does not include an invoiced business" do
        invoiced_business = create :business, name: "invoiced business", owners: [@owner]
        invoiced_business.customer.update(billing_type: Customer::BILLING_TYPE_INVOICE)
        assert_predicate invoiced_business, :invoiced?

        refute_includes Business.auto_pay_rbi_disabled, invoiced_business
      end

      test "does not include a self-serve business if auto-pay is enabled" do
        card_business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        refute_predicate card_business, :invoiced?

        card_business.enable_automatic_self_serve_payment(@owner)
        assert_predicate card_business, :automatic_self_serve_payment_enabled?

        refute_includes Business.auto_pay_rbi_disabled, card_business
      end

      test "includes a self-serve business if auto-pay is disabled due to RBI" do
        card_business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        refute_predicate card_business, :invoiced?

        card_business.enable_automatic_self_serve_payment(@owner, reason: :customer_initiated)
        assert_predicate card_business, :automatic_self_serve_payment_enabled?

        card_business.disable_auto_pay!(:india_rbi)
        card_business.disable_automatic_self_serve_payment(@owner)
        refute_predicate card_business.reload, :automatic_self_serve_payment_enabled?
        assert_includes card_business.customer.auto_pay_reasons, :india_rbi

        assert_includes Business.auto_pay_rbi_disabled, card_business
      end

      test "does not include a self-serve business if auto-pay is disabled for a different reason" do
        card_business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        refute_predicate card_business, :invoiced?

        card_business.enable_automatic_self_serve_payment(@owner, reason: :customer_initiated)
        assert_predicate card_business, :automatic_self_serve_payment_enabled?

        card_business.disable_auto_pay!(:customer_initiated)
        card_business.disable_automatic_self_serve_payment(@owner)
        refute_predicate card_business.reload, :automatic_self_serve_payment_enabled?
        refute_includes card_business.customer.auto_pay_reasons, :india_rbi

        refute_includes Business.auto_pay_rbi_disabled, card_business
      end
    end

    context "upgrade_purchase_initiated scope" do
      test "does not include a business not being upgraded" do
        business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]

        refute_includes Business.upgrade_purchase_initiated, business
      end

      test "does not include a trial business" do
        business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        business.update!(trial_expires_at: 1.day.from_now)
        assert_predicate business, :trial?

        refute_includes Business.upgrade_purchase_initiated, business
      end

      test "does not include a business who's upgrade has been initiated, but payment is not in progress" do
        business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        business.initiate_organization_upgrade(@owner)
        assert_predicate business, :organization_upgrade_initiated?

        refute_includes Business.upgrade_purchase_initiated, business
      end

      test "includes a business who's upgrade purchase payment is in progress" do
        business = create :business, :with_self_serve_payment, name: "card business", owners: [@owner]
        business.initiate_organization_upgrade(@owner)
        business.initiate_organization_upgrade_purchase(@owner)
        assert_predicate business, :organization_upgrade_purchase_initiated?

        assert_includes Business.upgrade_purchase_initiated, business
      end
    end
  end

  context "#destroy" do
    test "destroys a Business successfully" do
      id = @business.id

      @business.destroy!

      assert_nil Business.find_by(id: id)
    end

    test "destroying business destroys custom properties" do
      id = @business.id

      create :custom_property_definition, source: @business
      create :custom_property_definition, source: @business

      assert_equal 2, CustomPropertyDefinition.defined_by(@business).count

      assert_difference "CustomPropertyDefinition.count", -2 do
        @business.destroy!
      end

      assert_nil Business.including_deleted.find_by(id: @business.id)
      assert_equal 0, CustomPropertyDefinition.defined_by(@business).count

      assert_nil Business.find_by(id: id)
    end

    test "destroys a Business with a PrimaryAvatar successfully" do
      owner = @business.owners.first
      avatar = create(:avatar, owner: @business, uploader: owner)
      PrimaryAvatar.set(avatar, owner)
      id = @business.id

      @business.destroy!

      assert_nil Business.find_by(id: id)
    end

    unless GitHub.single_business_environment?
      test "destroys a soft-deleted Business with a PrimaryAvatar successfully" do
        owner = @deletable_business.owners.first
        avatar = create(:avatar, owner: @deletable_business, uploader: owner)
        PrimaryAvatar.set(avatar, owner)
        @deletable_business.soft_delete!
        id = @deletable_business.id

        @deletable_business.destroy!

        assert_nil Business.find_by(id: id)
      end
    end
  end

  context "for_query scope" do
    test "returns scoped businesses when query is blank" do
      results = Business.for_query("  ")
      assert_same_elements [
        @business,
        @deletable_business,
        @enterprise_managed_business,
        @another_business,
        @upgrading_business
      ], results
      results = Business.for_query(nil)
      assert_same_elements [
        @business,
        @deletable_business,
        @enterprise_managed_business,
        @another_business,
        @upgrading_business
      ], results
    end

    test "returns businesses where slug matches query" do
      results = Business.for_query("cde")
      assert_includes results, @business
    end

    test "returns businesses where slug case-insensitively matches query" do
      results = Business.for_query("cdE-l")
      assert_includes results, @business
    end

    test "returns businesses where name matches query" do
      @business.update! name: "Now with a different name"
      results = Business.for_query("different")
      assert_includes results, @business
    end

    test "returns businesses where name matches upper case query" do
      @business.update! name: "DIFFERENT NAME"
      results = Business.for_query("DIFFERENT NAME")
      assert_includes results, @business
    end

    test "returns businesses where name case-insensitively matches query" do
      @business.update! name: "Now with a different name"
      results = Business.for_query("a DIFFERENT Name")
      assert_includes results, @business
    end
  end unless GitHub.single_business_environment?

  context "#url_change_supported?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute_predicate @business, :url_change_supported?
      end
    else
      test "returns false for EMU business" do
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :url_change_supported?
      end

      test "returns true for ongoing trial business" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.reload

        assert_predicate @business, :default_managed?
        assert_predicate @business, :trial?
        refute_predicate @business, :trial_expired?
        assert_predicate @business, :url_change_supported?
      end

      test "returns true for an expired trial business" do
        @business.update_attribute :trial_expires_at, 2.days.ago
        @business.reload

        assert_predicate @business, :default_managed?
        assert_predicate @business, :trial?
        assert_predicate @business, :trial_expired?
        assert_predicate @business, :url_change_supported?
      end

      test "returns false for a spammy business" do
        @business.mark_as_spammy

        refute_predicate @business, :url_change_supported?
      end
    end
  end

  context "#self_serve_url_change_permitted?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute_predicate @business, :self_serve_url_change_permitted?
      end
    else
      test "returns false for invoiced business" do
        assert_predicate @business, :invoiced?
        assert_predicate @business, :url_change_supported?

        refute_predicate @business, :self_serve_url_change_permitted?
      end

      test "returns true for business where url change is supported, and business is on self-serve payment" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        assert_predicate @business, :self_serve_payment?
        assert_predicate @business, :url_change_supported?

        assert_predicate @business, :self_serve_url_change_permitted?
      end
    end
  end

  context "#self_serve_deletion_supported?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute_predicate @business, :self_serve_deletion_supported?
      end
    elsif GitHub.multi_tenant_enterprise?
      test "returns false in multi tenant enterprise" do
        refute_predicate @business, :self_serve_deletion_supported?
      end
    else
      test "returns false for trial business" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.reload

        assert_predicate @business, :trial?
        refute_predicate @business, :self_serve_deletion_supported?
      end

      test "returns false for sales managed non-metered default managed business" do
        assert_predicate @business, :sales_managed?
        refute_predicate @business, :metered_ghe?
        assert_predicate @business, :default_managed?
        refute_predicate @business, :self_serve_deletion_supported?
      end

      test "returns false for sales managed metered default managed business" do
        @business.customer.update! metered_ghe: true
        @business.reload

        assert_predicate @business, :sales_managed?
        assert_predicate @business, :metered_ghe?
        assert_predicate @business, :default_managed?
        refute_predicate @business, :self_serve_deletion_supported?
      end

      test "returns true for unmanaged non-metered default managed business" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @business.reload

        refute_predicate @business, :sales_managed?
        refute_predicate @business, :metered_ghe?
        assert_predicate @business, :default_managed?
        assert_predicate @business, :self_serve_deletion_supported?
      end

      test "returns true for unmanaged metered default managed business" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD, metered_ghe: true
        @business.reload

        refute_predicate @business, :sales_managed?
        assert_predicate @business, :metered_ghe?
        assert_predicate @business, :default_managed?
        assert_predicate @business, :self_serve_deletion_supported?
      end

      test "returns false for sales managed non-metered EMU business" do
        assert_predicate @enterprise_managed_business, :sales_managed?
        refute_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end

      test "returns false for sales managed metered EMU business" do
        @enterprise_managed_business.customer.update! metered_ghe: true
        @enterprise_managed_business.reload

        assert_predicate @enterprise_managed_business, :sales_managed?
        assert_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end

      test "returns false for unmanaged non-metered EMU business when FF disabled" do
        disable_feature_flag(:self_serve_emu_ea_deletion)
        @enterprise_managed_business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @enterprise_managed_business.reload

        refute_predicate @enterprise_managed_business, :sales_managed?
        refute_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end

      test "returns false for unmanaged metered EMU business when FF disabled" do
        disable_feature_flag(:self_serve_emu_ea_deletion)
        @enterprise_managed_business.customer.update! billing_type: Customer::BILLING_TYPE_CARD, metered_ghe: true
        @enterprise_managed_business.reload

        refute_predicate @enterprise_managed_business, :sales_managed?
        assert_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end

      test "returns true for unmanaged non-metered EMU business when FF enabled" do
        enable_feature_flag(:self_serve_emu_ea_deletion)
        @enterprise_managed_business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @enterprise_managed_business.reload

        refute_predicate @enterprise_managed_business, :sales_managed?
        refute_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        assert_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end

      test "returns true for unmanaged metered EMU business when FF enabled" do
        enable_feature_flag(:self_serve_emu_ea_deletion)
        @enterprise_managed_business.customer.update! billing_type: Customer::BILLING_TYPE_CARD, metered_ghe: true
        @enterprise_managed_business.reload

        refute_predicate @enterprise_managed_business, :sales_managed?
        assert_predicate @enterprise_managed_business, :metered_ghe?
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        assert_predicate @enterprise_managed_business, :self_serve_deletion_supported?
      end
    end
  end

  context "#self_serve_deletion_permitted?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute_predicate @business, :self_serve_deletion_permitted?
      end
    else
      test "returns false for Business that is supported but still has member orgs" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @business.reload
        assert_predicate @business.organization_ids, :any?

        refute_predicate @business, :self_serve_deletion_permitted?
      end

      test "returns true for Business that is supported and has no member orgs" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @business.reload
        @business.remove_organization(@org1)
        @business.remove_organization(@org2)
        assert_predicate @business.organization_ids, :empty?

        assert_predicate @business, :self_serve_deletion_permitted?
      end
    end
  end

  context "#soft_deleted_businesses_for" do
    unless GitHub.single_business_environment?
      test "returns any deleted business the user was a member of" do
        assert_equal [], Business.soft_deleted_businesses_for(@owner).pluck(:id)
        @deletable_business.soft_delete!
        assert_equal [@deletable_business.id], Business.soft_deleted_businesses_for(@owner).pluck(:id)
      end

      test "returns deleted business the user was the emu admin of" do
        enterprise_managed_business = create(:emu).enterprise_managed_business
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: enterprise_managed_business.id)
        emu_admin = enterprise_managed_business.user_accounts.roles([:emu_admin]).first.user
        assert_equal [], Business.soft_deleted_businesses_for(emu_admin, emu_admin: true).pluck(:id)
        enable_feature_flag(:emu_ea_deletion)
        enterprise_managed_business.soft_delete!(actor: enterprise_managed_business.owners.first)
        assert_equal [enterprise_managed_business.id], Business.soft_deleted_businesses_for(emu_admin, emu_admin: true).pluck(:id)
      end
    end
  end

  context "#expired_trial_businesses_for" do
    unless GitHub.single_business_environment?
      test "returns a cancelled trial business the user was a member of" do
        business = create :business,  :with_self_serve_payment, trial_expires_at: 1.day.from_now, owners: [@owner]
        assert_equal [], Business.cancelled_trial_businesses_for(@owner).pluck(:id)
        business.cancel_trial(@owner)
        assert_equal [business.id], Business.cancelled_trial_businesses_for(@owner).pluck(:id)
      end

      test "returns a cancelled trial business the user was the emu admin of" do
        emu_business = create :business, :enterprise_managed, trial_expires_at: 1.day.from_now
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: emu_business.id)
        emu_admin = emu_business.user_accounts.roles([:emu_admin]).first.user
        assert_equal [], Business.cancelled_trial_businesses_for(emu_admin, emu_admin: true).pluck(:id)
        emu_business.cancel_trial(emu_admin)
        assert_equal [emu_business.id], Business.cancelled_trial_businesses_for(emu_admin).pluck(:id)
      end
    end
  end

  context "#soft_delete!" do
    if GitHub.single_business_environment?
      test "raises Business::SoftDeletionUnsupportedError in single business environment" do
        assert_raises Business::SoftDeletionUnsupportedError do
          @business.soft_delete!
        end
      end
    else
      test "raises Business::SoftDeletionUnsupportedError if business has member organizations" do
        assert_predicate @business.organizations, :any?

        assert_raises Business::SoftDeletionUnsupportedError do
          @business.soft_delete!(actor: @owner, self_serve: true)
        end
      end

      test "raises Business::SoftDeletionUnsupportedError if business has delete restricted trade screening status" do
        enable_feature_flag(:live_sdn_screening, @deletable_business)
        create(:account_screening_profile, :with_business, :true_match, owner: @deletable_business)
        refute_predicate @deletable_business, :deleted?

        assert_raises_with_message(Business::SoftDeletionUnsupportedError, "Soft-deletion is not permitted for enterprises with trade restrictions") do
          @deletable_business.soft_delete!
        end
      end if GitHub.billing_enabled?

      test "does not raise Business::SoftDeletionUnsupportedError if business has non-delete restricted trade screening status" do
        enable_feature_flag(:live_sdn_screening, @deletable_business)
        create(:account_screening_profile, :with_business, :data_issue, owner: @deletable_business)
        refute_predicate @deletable_business, :deleted?

        @deletable_business.soft_delete!
        assert_predicate @deletable_business, :deleted?
      end if GitHub.billing_enabled?

      test "raises Business::SoftDeletionUnsupportedError for EMU business with feature flags disabled" do
        disable_feature_flag(:emu_ea_deletion)
        disable_feature_flag(:self_serve_emu_ea_deletion)
        assert_predicate @enterprise_managed_business, :enterprise_managed?

        assert_raises Business::SoftDeletionUnsupportedError do
          @enterprise_managed_business.soft_delete!
        end
      end

      test "deletes EMU business with stafftools feature flag enabled" do
        enable_feature_flag(:emu_ea_deletion)
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :deleted?

        @enterprise_managed_business.soft_delete!(actor: @enterprise_managed_business.owners.first, self_serve: true)
        assert_predicate @enterprise_managed_business, :deleted?
      end

      test "deletes EMU business with self-serve deletion feature flag enabled" do
        enable_feature_flag(:self_serve_emu_ea_deletion)
        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute_predicate @enterprise_managed_business, :deleted?

        @enterprise_managed_business.soft_delete!
        assert_predicate @enterprise_managed_business, :deleted?
      end

      test "soft deletes business orgs" do
        assert_predicate @business.organizations, :any?
        assert_equal 1, @business.soft_deleted_organizations.count

        perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
          @business.soft_delete!(actor: @owner)
        end

        assert_predicate @business, :deleted?

        assert_equal 3, @business.reload.soft_deleted_organizations.count
      end

      test "marks business as deleted" do
        refute_predicate @deletable_business, :deleted?
        assert_nil @deletable_business.deleted_at

        @deletable_business.soft_delete!

        assert_predicate @deletable_business, :deleted?
        refute_nil @deletable_business.deleted_at
      end

      test "destroys all associated EnterpriseInstallations" do
        refute_predicate @deletable_business, :deleted?
        installation = create :enterprise_installation, owner: @deletable_business
        assert_same_elements [installation], @deletable_business.enterprise_installations

        perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
          @deletable_business.soft_delete!
        end

        assert_predicate @deletable_business, :deleted?
        deleted = Business.deleted.find(@deletable_business.id)
        assert_empty deleted.enterprise_installations
      end

      test "suspends EMU first admin user" do
        enable_feature_flag(:emu_ea_deletion)
        owner = create(:emu, :owner)
        emu_business = owner.enterprise_managed_business
        refute_predicate emu_business.find_first_emu_owner, :suspended?

        emu_business.soft_delete!(actor: owner)

        assert_predicate emu_business.find_first_emu_owner, :suspended?
        assert_predicate emu_business, :deleted?
      end

      test "removes all EMU external identity sessions" do
        enable_feature_flag(:emu_ea_deletion)
        emu = create :emu
        emu_business = emu.enterprise_managed_business
        session = create :user_session, user: emu
        external_identity_session = create :external_identity_session, external_identity: emu.external_identities.first, user_session: session

        perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
          emu_business.soft_delete!(actor: emu_business.owners.first)
        end

        assert_predicate emu_business, :deleted?
        assert_empty emu_business.external_provider.external_identity_sessions
      end

      test "does not fail when org admins presence validation fails" do
        assert_equal 1, @business.soft_deleted_organizations.count

        Organization.any_instance.stubs(:admins).returns([])
        perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
          @business.soft_delete!(actor: @owner)
        end

        assert_predicate @business, :deleted?

        assert_equal 3, @business.reload.soft_deleted_organizations.count
      end

      test "closes Zuora account" do
        staff = create :staff_admin_user
        @deletable_business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

        @deletable_business.enable_automatic_self_serve_payment(staff)
        assert_predicate @deletable_business, :automatic_self_serve_payment_enabled?

        plan_subscription = create(:billing_plan_subscription, :zuora_business, customer: @deletable_business.customer)

        perform_enqueued_jobs only: [SoftDeleteBusinessJob, CloseOutZuoraSubscriptionJob] do
          # Zuora subscription is closed
          close_subscription_mock = Minitest::Mock.new
          close_subscription_mock.expect(:success?, true)
          ::Billing::CloseZuoraSubscription.expects(:perform).once.with(
            zuora_subscription_number: @deletable_business.plan_subscription.zuora_subscription_number,
            plan_subscription: @deletable_business.plan_subscription,
            collect_payment: false
          ).returns(close_subscription_mock)

          @deletable_business.soft_delete!

          # Ensure auto-pay isn't changed
          assert_predicate @deletable_business.reload, :automatic_self_serve_payment_enabled?
          assert_predicate @deletable_business, :deleted?
        end
      end

      test "closes Zuora account and collects payment when self_serve provided as true" do
        staff = create :staff_admin_user
        @deletable_business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

        @deletable_business.enable_automatic_self_serve_payment(staff)
        assert_predicate @deletable_business, :automatic_self_serve_payment_enabled?

        plan_subscription = create(:billing_plan_subscription, :zuora_business, customer: @deletable_business.customer)

        perform_enqueued_jobs only: [SoftDeleteBusinessJob, CloseOutZuoraSubscriptionJob] do
          # Zuora subscription is closed
          close_subscription_mock = Minitest::Mock.new
          close_subscription_mock.expect(:success?, true)
          ::Billing::CloseZuoraSubscription.expects(:perform).once.with(
            zuora_subscription_number: @deletable_business.plan_subscription.zuora_subscription_number,
            plan_subscription: @deletable_business.plan_subscription,
            collect_payment: true
          ).returns(close_subscription_mock)

          @deletable_business.soft_delete! self_serve: true

          # Ensure auto-pay isn't changed
          assert_predicate @deletable_business.reload, :automatic_self_serve_payment_enabled?
          assert_predicate @deletable_business, :deleted?
        end
      end

      test "sends email when self_serve is passed as true" do
        assert_performed_email(
          mailer: "BusinessMailer",
          action: "business_deleted",
          args: [@owner, @deletable_business.id]
        ) do
          @deletable_business.soft_delete!(actor: @owner, self_serve: true)
        end
      end

      test "sends email when self_serve is passed as true without actor" do
        assert_performed_email(
          mailer: "BusinessMailer",
          action: "business_deleted",
          args: [nil, @deletable_business.id]
        ) do
          @deletable_business.soft_delete!(self_serve: true)
        end
      end

      test "handles soft-deleted Business when email delivery enqueued with #deliver_later" do
        perform_enqueued_jobs only: [ApplicationDeliveryJob] do
          assert_difference "ActionMailer::Base.deliveries.size", +1 do
            @deletable_business.soft_delete!(actor: @owner, self_serve: true)
          end
        end
      end
    end
  end

  context "#deleted?" do
    test "returns false when deleted_at is not set" do
      refute_predicate @business, :deleted?
    end

    test "returns true when deleted_at is set" do
      @business.touch :deleted_at
      assert_predicate @business, :deleted?
    end
  end

  context "stafftools_deletion_disabled?" do
    if GitHub.single_business_environment?
      test "returns true in single business environment" do
        assert @business.stafftools_deletion_disabled?(@owner)
      end
    elsif GitHub.multi_tenant_enterprise?
      test "returns true in multi tenant enterprise if FF disabled" do
        disable_feature_flag(:proxima_tenant_deletion, @owner)
        assert @business.stafftools_deletion_disabled?(@owner)
      end

      test "returns false in multi tenant enterprise if FF enabled" do
        enable_feature_flag(:proxima_tenant_deletion, @owner)
        refute @business.stafftools_deletion_disabled?(@owner)
      end

      test "returns true in multi tenant enterprise if FF enabled and tenant is a stafftools tenant" do
        enable_feature_flag(:proxima_tenant_deletion, @owner)
        Business.any_instance.stubs(:stafftools_tenant?).returns(true)
        assert @business.stafftools_deletion_disabled?(@owner)
      end
    else
      test "returns false for invoiced default managed business" do
        assert_predicate @business, :invoiced?
        assert_predicate @business, :default_managed?
        refute @business.stafftools_deletion_disabled?(@owner)
      end

      test "returns false for self-serve paying default managed business" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @business.reload

        assert_predicate @business, :self_serve_payment?
        assert_predicate @business, :default_managed?
        refute @business.stafftools_deletion_disabled?(@owner)
      end

      test "returns true for enterprise managed business with feature flag disabled" do
        disable_feature_flag(:emu_ea_deletion, @owner)

        assert_predicate @enterprise_managed_business, :enterprise_managed?
        assert @enterprise_managed_business.stafftools_deletion_disabled?(@owner)
      end

      test "returns false for enterprise managed business with feature flag enabled" do
        enable_feature_flag(:emu_ea_deletion, @owner)

        assert_predicate @enterprise_managed_business, :enterprise_managed?
        refute @enterprise_managed_business.stafftools_deletion_disabled?(@owner)
      end
    end
  end

  context "#restore!" do
    test "marks business as not deleted" do
      @deletable_business.soft_delete!
      assert_predicate @deletable_business, :deleted?
      @deletable_business.restore!
      refute_predicate @deletable_business, :deleted?
    end

    test "resumes the billing of a business with self-serve billing" do
      plan_subscription = create(:billing_plan_subscription, customer: @deletable_business.customer)
      @deletable_business.soft_delete!

      # Ensure plan subscription is resumed
      assert_enqueued_with(job: ResumePlanSubscriptionJob, args: [plan_subscription]) do
        @deletable_business.restore!
      end
    end

    test "sets deletion date for expired trial" do
      expired_trial = create :business, :with_self_serve_payment, trial_expires_at: Time.now
      enable_feature_flag(:expired_trial_deletion, expired_trial)
      Timecop.freeze(Business::RESTORABLE_PERIOD.from_now + 1.day) do
        expired_trial.expire_trial
        perform_enqueued_jobs(only: [SoftDeleteBusinessJob]) do
          expired_trial.soft_delete!
        end

        assert expired_trial.reload.deleted?
        initial_deletion_date = expired_trial.trial_deleted_at

        expired_trial.restore!
        refute_equal initial_deletion_date, expired_trial.reload.trial_deleted_at
        assert_equal 8.days.from_now.to_date, expired_trial.trial_deleted_at.to_date, "Expected deletion date to be #{8.days.from_now.to_date}"
      end
    end

    test "restores soft-deleted organizations" do
      organization = create(:organization, login: "ano-soft-deleted-org", business: @deletable_business)
      perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
        @deletable_business.soft_delete!(actor: @owner)
      end

      assert_predicate organization.reload, :soft_deleted?
      assert @deletable_business.has_sufficient_licenses_for_organization?(organization)

      perform_enqueued_jobs only: [RestoreSoftDeletedBusinessOrganizationsJob] do
        @deletable_business.restore!
      end

      assert_empty @deletable_business.reload.soft_deleted_organizations
    end
  end unless GitHub.single_business_environment?

  context "#site_admin_audit_log_query" do
    test "returns Elasticsearch query by default and when specified" do
      assert_equal \
        "business_id:#{@business.id}",
        @business.site_admin_audit_log_query
      assert_equal \
        "business_id:#{@business.id}",
        @business.site_admin_audit_log_query(driftwood_ade: false)
    end

    test "returns Driftwood ADE query when specified" do
      assert_equal \
        "webevents | where business_id == #{@business.id}",
        @business.site_admin_audit_log_query(driftwood_ade: true)
    end
  end

  context "#role_for" do
    test "returns owner role for an owner" do
      assert_equal @business.role_for(@owner), Business::OWNER_ROLE
    end

    test "returns billing_manager role for a billing manager" do
      assert_equal @business.role_for(@billing_manager), Business::BILLING_MANAGER_ROLE
    end

    test "returns member role for a member" do
      assert_equal @business.role_for(@member1), :member
    end

    unless GitHub.single_business_environment?
      test "returns unaffiliated for a unaffiliated member" do
        enable_feature_flag(:unaffiliated_user_accounts)
        @business.add_user_accounts([@user.id], business_roles_bitfield: 0)
        assert_equal @business.role_for(@user), :unaffiliated
      end

      test "returns unaffiliated for a unaffiliated member in basic enterprise" do
        disable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        @business.update(seats_plan_type: :basic)
        @business.add_user_accounts([@user.id], business_roles_bitfield: 0)
        assert_equal @business.role_for(@user), :unaffiliated
      end

      test "returns nil for a unaffiliated member" do
        disable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        @business.add_user_accounts([@user.id], business_roles_bitfield: 0)
        assert_nil @business.role_for(@user)
      end
    end

    test "returns nil for a non-member" do
      assert_nil @business.role_for(@user)
    end
  end

  context "#safe_description" do
    test "runs the business description through the profile bio pipeline" do
      @business.update description: "BEST ENTERPRISE :popcorn:"
      expected = %(<div>BEST ENTERPRISE 🍿</div>)
      assert_equal expected, @business.safe_description
    end
  end

  context "#name" do
    test "supports encoded characters" do
      @business.update! name: "Emoji Corp #{GRIN_EMOJI}"
      @business.reload
      assert_equal "Emoji Corp #{GRIN_EMOJI}", @business.name
    end
  end

  context "#slug" do
    if GitHub.single_business_environment?
      test "generated with default value global-enterprise in single busines env when parameterised name would be empty string" do
        Business.delete_all
        business = create :business, name: "🌈🌈🌈🌈🌈"
        assert_equal "global-enterprise", business.slug
      end
    else
      test "is generated automaticatically during creation" do
        business = create :business, name: "Acme Corp."
        assert_equal "acme-corp", business.slug
      end

      test "generated with default value business in multi business env when parameterised name would be empty string" do
        business = create :business, name: "🌈🌈🌈🌈🌈"
        assert_equal "enterprise", business.slug
      end

      test "generated uniquely in multi business env with default value when duplicate exists" do
        business = create :business, name: "🌈🌈🌈🌈🌈"
        assert_equal "enterprise", business.slug

        another_business = create :business, name: "🌈🌈🌈🌈🌈🌈🌈🌈🌈🌈"
        assert_equal "enterprise-2", another_business.slug
      end

      test "generated uniquely if another with the same slug exists" do
        create :business, name: "Acme Corp."

        business2 = create :business, name: "Acme Corp."
        assert_equal "acme-corp-2", business2.slug

        business3 = create :business, name: "Acme Corp."
        assert_equal "acme-corp-3", business3.slug
      end

      test "generated uniquely if another soft-deleted business with the same slug exists" do
        create :business, name: "Acme Corp."

        business2 = create :business, name: "Acme Corp."
        assert_equal "acme-corp-2", business2.slug

        business2.soft_delete!

        business3 = create :business, name: "Acme Corp."
        assert_equal "acme-corp-3", business3.slug
      end

      test "ensures generated slugs don't exceed the max length" do
        long_name = "blah" * 15
        assert_equal 60, long_name.length

        business = create :business, name: long_name
        assert_equal 60, business.slug.length
        assert business.slug.ends_with?("blah")

        2.upto(9) do |dup|
          business = create :business, name: long_name
          assert_equal 60, business.slug.length
          assert business.slug.ends_with?("bl-#{dup}")
        end

        business = create :business, name: long_name
        assert_equal 60, business.slug.length
        assert business.slug.ends_with?("b-10")
      end
    end
  end

  context "#rename_slug" do
    test "returns true when slug is successfully changed" do
      assert @business.rename_slug("i-am-the-new-slug", actor: @owner)
      assert_equal "i-am-the-new-slug", @business.reload.slug
    end

    test "returns false when slug is invalid" do
      slug_was = @business.slug.dup
      refute @business.rename_slug("I AM NOT A SLUG", actor: @owner)
      assert_equal slug_was, @business.reload.slug
    end

    test "returns true if successfully updated even if unchanged" do
      slug_was = @business.slug.dup
      assert @business.rename_slug(slug_was, actor: @owner)
      assert_equal slug_was, @business.reload.slug
    end

    test "instruments business.rename_slug when slug is successfully renamed" do
      slug_was = @business.slug.dup

      events = assert_performed_audit_entries(count: 1, only: "business.rename_slug") do
        @business.rename_slug("i-am-the-new-slug", actor: @owner)
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        actor: @owner.login,
        actor_id: @owner.id,
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        slug_was: slug_was,
        slug: "i-am-the-new-slug",
      }
      assert_subset_hash expected_payload, events.first

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@business),
        slug_was: slug_was,
        slug: "i-am-the-new-slug"
      }, schema: "github.enterprise_account.v0.EnterpriseRenameSlug")
    end

    test "does not instrument when slug is invalid" do
      events = assert_performed_audit_entries(count: 0, only: "business.rename_slug") do
        refute @business.rename_slug("I AM NOT A SLUG", actor: @owner)
      end
      assert events.empty?
    end

    test "does not instrument when slug doesn't change" do
      slug_was = @business.slug.dup
      events = assert_performed_audit_entries(count: 0, only: "business.rename_slug") do
        assert @business.rename_slug(slug_was, actor: @owner)
      end
      assert events.empty?
    end

    if GitHub.spamminess_check_enabled?
      test "does not rename slug if the business is spammy and the actor is not a site admin" do
        rando = create :user
        @business.add_owner(rando, actor: @owner)
        original_slug = @business.slug.dup
        @business.mark_as_spammy

        refute_predicate rando, :site_admin?
        assert_predicate @business, :spammy?

        refute @business.rename_slug("new-slug", actor: rando)
        assert_equal original_slug, @business.reload.slug
      end

      test "renames slug if the business is spammy but the actor is a site admin" do
        site_admin = create :staff_admin_user

        original_slug = @business.slug.dup
        @business.mark_as_spammy

        assert_predicate site_admin, :site_admin?
        assert_predicate @business, :spammy?

        assert @business.rename_slug("new-slug", actor: site_admin)
        assert_equal "new-slug", @business.reload.slug
        refute_equal original_slug, @business.reload.slug
      end
    end
  end

  context "#business_type" do
    test "cannot be modified once a business is created" do
      @enterprise_managed_business.update business_type: "default_managed"
      refute_predicate @enterprise_managed_business, :valid?
      assert_includes @enterprise_managed_business.errors[:business_type], "Cannot change an existing business type"
    end
  end unless GitHub.single_business_environment?

  context "#to_s" do
    test "is aliased to slug" do
      assert_equal @business.slug, @business.to_s
    end
  end

  context "#to_param" do
    test "uses the slug for pretty URLs" do
      assert_equal @business.slug, @business.to_param
    end
  end

  context "#display_login" do
    test "is aliased to slug" do
      assert_equal @business.slug, @business.display_login
    end
  end

  context "::by_slug" do
    test "orders businesses by slug" do
      bcd = create :business, name: "BCD Ltd"
      abc = create :business, name: "ABC Ltd"
      results = Business.where(id: [@business.id, bcd.id, abc.id]).by_slug
      assert_equal %w[abc-ltd bcd-ltd cde-ltd], results.pluck(:slug)
    end
  end unless GitHub.single_business_environment?

  context "#description" do
    test "supports encoded characters" do
      @business.update! description: "Happy to help #{GRIN_EMOJI}"
      @business.reload
      assert_equal "Happy to help #{GRIN_EMOJI}", @business.description
    end
  end

  context "#long_description" do
    test "supports encoded characters" do
      @business.update! long_description: "Happy to help #{GRIN_EMOJI}"
      @business.reload
      assert_equal "Happy to help #{GRIN_EMOJI}", @business.long_description
    end
  end

  context "#long_description_html" do
    test "returns empty string by default" do
      assert_equal "", @business.long_description_html
    end

    test "supports bulleted lists" do
      @business.update! long_description: "- a nice thing"
      assert_match %r{<ul>\s+<li>a nice thing</li>\s+</ul>}, @business.long_description_html
    end

    test "supports markdown links" do
      @business.update! long_description: "[example](https://example.com)"
      assert_equal %Q[<p><a href="https://example.com">example</a></p>], @business.long_description_html
    end

    test "supports markdown links in heading 1s" do
      @business.update! long_description: "# [example](https://example.com)"
      assert_equal %Q[<h1><a href="https://example.com">example</a></h1>], @business.long_description_html
    end

    test "supports colon-style emoji" do
      @business.update! long_description: ":smile:"
      doc = Nokogiri::HTML.fragment(@business.long_description_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "supports native emoji" do
      @business.update! long_description: GRIN_EMOJI
      doc = Nokogiri::HTML.fragment(@business.long_description_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "camouflages externally hosted image URLs" do
      input = "a nice thing ![octocat](https://myoctocat.com/assets/images/base-octocat.svg)"
      @business.update! long_description: input

      expected_output = "<p>a nice thing <img src=\"https://camo.githubapp.com/1ce8f74feaf535357f3a1097892d0125ff39a1ae213e6d25803ecae6018cab56/68747470733a2f2f6d796f63746f6361742e636f6d2f6173736574732f696d616765732f626173652d6f63746f6361742e737667\" alt=\"octocat\" data-canonical-src=\"https://myoctocat.com/assets/images/base-octocat.svg\"></p>"
      assert_equal expected_output, @business.long_description_html
    end

    test "supports @mentions" do
      user = @business.owners.first
      expected_link = "<a class=\"user-mention notranslate\" data-hovercard-type=\"user\" " +
        "data-hovercard-url=\"/users/#{user.login}/hovercard\" " +
        "data-octo-click=\"hovercard-link-click\" data-octo-dimensions=\"link_type:self\" " +
        "href=\"https://github.com/#{user.login}\">@#{user.login}</a>"

      @business.update! long_description: "@#{user.login}"
      assert_equal "<p>#{expected_link}</p>", @business.long_description_html
    end
  end

  context "#terms_of_service_company_name" do
    test "gets a default value from the value of name" do
      assert_equal @business.name, @business.terms_of_service_company_name
    end

    test "supports encoded characters" do
      @business.update! terms_of_service_company_name: "Emoji Corp #{GRIN_EMOJI}"
      assert_equal "Emoji Corp #{GRIN_EMOJI}", @business.terms_of_service_company_name
    end
  end unless GitHub.single_business_environment?

  context "#user_removal_available?" do
    if GitHub.single_business_environment?
      test "returns false in enterprise runtime mode" do
        refute @business.user_removal_available?
      end
    else
      test "returns true in dotcom runtime mode" do
        assert @business.user_removal_available?
      end

      test "returns false in dotcom for expired trial" do
        free_org = create :organization, plan: GitHub::Plan.free
        trial_business = create :business, \
          :with_self_serve_payment,
          name: "Upgraded org to trial",
          upgraded_at: 2.days.ago,
          upgraded_from: free_org,
          upgraded_from_plan: free_org.plan.name
        trial_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        trial_business.expire_trial

        refute trial_business.user_removal_available?
      end

      test "returns false in dotcom runtime mode if EMU enterprise" do
        emu_owner = create :emu, :owner
        emu_enterprise = emu_owner.enterprise_managed_business
        emu = create :emu, business: emu_enterprise
        refute emu_enterprise.user_removal_available?
      end
    end
  end

  context "#remove_member" do
    test "raises an error if the user is in no way a member of the enterprise" do
      rando = create :user
      message = "User #{rando.login} doesn't belong to #{@business.name}"
      assert_raises_with_message(Business::InvalidRemovalError, message) do
        @business.remove_member(rando, actor: @owner)
      end
    end

    test "raises an error if a billing manager of the enterprise attempts to remove a member" do
      message = "#{@billing_manager} does not have permission to remove a user from this enterprise"
      assert_raises_with_message(Business::ForbiddenRemovalError, message) do
        @business.remove_member(@member1, actor: @billing_manager)
      end
    end

    test "raises an error if the member is the last admin of the enterprise" do
      message = "User #{@owner.login} is the last admin in the #{@business.name} enterprise"
      assert_raises_with_message Business::NoAdminsError, message do
        @business.remove_member(@owner, actor: @owner)
      end
    end

    test "raises an error if the member is the last admin of any enterprise organization" do
      last_admin = @org1.admins.first
      10.times do |n|
        org = create(:business_plus_organization, login: "member-org-#{n}", admin: last_admin)
        @business.add_organization(org)
      end

      orgs_part = last_admin.solitarily_owned_organizations.order(:login).map(&:display_login).join(", ")
      message = "User #{last_admin.display_login} is the last admin in these organizations: #{orgs_part}"
      assert_query_count(10, ignore_feature_flags: true) do
        assert_raises_with_message(Organization::NoAdminsError, message) do
          @business.remove_member(last_admin, actor: @owner)
        end
      end
    end

    test "does not raise an error if a non-owner of the enterprise attempts to remove a member and force is true" do
      second_owner = create :user, login: "second-owner"
      @business.add_owner(second_owner, actor: @owner)
      assert @business.owner?(second_owner)
      refute_error_reported do
        @business.remove_member(second_owner, actor: create(:user), force: true)
      end
      refute @business.owner?(second_owner)
    end

    test "revokes an enterprise admin's privileges" do
      second_owner = create :user, login: "second-owner"
      @business.add_owner(second_owner, actor: @owner)

      assert @business.owner?(second_owner)
      @business.remove_member(second_owner, actor: @owner)
      refute @business.owner?(second_owner)
    end

    test "cancels an enterprise owner's invitation" do
      second_owner = create :user
      @business.invite_admin(user: second_owner, role: "owner", inviter: @owner)

      assert @business.pending_admin_invitation_for(second_owner, role: "owner")
      @business.remove_member(second_owner, actor: @owner)
      refute @business.pending_admin_invitation_for(second_owner, role: "owner")
    end

    test "revokes a enterprise billing manager's privileges" do
      assert @business.billing_manager?(@billing_manager)
      @business.remove_member(@billing_manager, actor: @owner)
      refute @business.billing_manager?(@billing_manager)
    end

    test "cancels an enterprise billing manager's invitation" do
      second_billing_manager = create :user
      @business.invite_admin(user: second_billing_manager, role: "billing_manager", inviter: @owner)

      assert @business.pending_admin_invitation_for(second_billing_manager, role: "billing_manager")
      @business.remove_member(second_billing_manager, actor: @owner)
      refute @business.pending_admin_invitation_for(second_billing_manager, role: "billing_manager")
    end

    test "removes a member from all of the enterprise organizations they can access" do
      assert @business.organization_members.include?(@member1)
      assert @org1.member?(@member1)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @business.remove_member(@member1, actor: @owner)
      end

      refute @business.organization_members.include?(@member1)
      refute @org1.member?(@member1)
    end

    test "removes an outside collaborator from any enterprise org repos they can access" do
      assert @business.outside_collaborators.include?(@collaborator)
      assert @org1.user_is_outside_collaborator?(@collaborator.id)

      @business.remove_member(@collaborator, actor: @owner)

      refute @business.outside_collaborators.include?(@collaborator)
      refute @org1.user_is_outside_collaborator?(@collaborator.id)
    end

    test "enterprise organization member invitations get cancelled" do
      invitation = @org2.invite(@member1, inviter: @org2.admins.first)
      assert @org2.pending_members.include?(@member1)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob]) do
        @business.remove_member(@member1, actor: @owner)
      end

      refute @org2.pending_members.include?(@member1)
      assert invitation.reload.cancelled?
    end

    test "members only connected to the enterprise via a pending invitation are removed" do
      new_member = create :user
      invitation = @org2.invite(new_member, inviter: @org2.admins.first)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob]) do
        @business.remove_member(new_member, actor: @owner)
      end

      refute @org2.pending_members.include?(new_member)
      assert invitation.reload.cancelled?
    end

    test "enterprise org repo outside collaborator invitations get cancelled" do
      RepositoryInvitation.invite_to_repo_with_confirmation(@collaborator, @org2.admins.first, @repo2)
      assert @repo2.invitees.include?(@collaborator)

      @business.remove_member(@collaborator, actor: @owner)

      refute @repo2.invitees.include?(@collaborator)
      refute RepositoryInvitation.where(invitee: @collaborator, inviter: @org2.admins.first, repository: @repo2).exists?
    end

    test "enterprise organization billing managers get removed" do
      rando = create :user
      @org2.billing.add_manager(rando, actor: @org2.admins.first)
      assert @org2.billing_manager?(rando)

      @business.remove_member(rando, actor: @owner)

      refute @org2.reload.billing_manager?(rando)
    end

    test "unaffiliated member gets removed" do
      enable_feature_flag(:unaffiliated_user_accounts)
      rando = create :user
      @business.add_user_accounts([rando.id])

      @business.remove_member(rando, actor: @owner)

      refute @org2.reload.billing_manager?(rando)
    end

    test "instruments removing a business_member when validations pass" do
      events = assert_performed_audit_entries(count: 1, only: "business.remove_member") do
        @business.remove_member(@collaborator, actor: @owner, reason: "removed_via_api")
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        name: @business.name,
        reason: "removed_via_api",
        business: @business.slug,
        business_id: @business.id,
        user: @collaborator.login,
        user_id: @collaborator.id,
        actor: @owner.login,
        actor_id: @owner.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "instruments nothing when removing a business_member when validations fail" do
      rando = create :user

      events = assert_performed_audit_entries(count: 0, only: "business.remove_member") do
        assert_raises Business::InvalidRemovalError do
          @business.remove_member(rando, actor: @owner)
        end
      end
      assert events.empty?
    end
  end unless GitHub.single_business_environment?

  context "#remove_members_who_are_only_members_of_these_orgs" do
    test "removes a member if they are only a member of the provided orgs" do
      disable_feature_flag(:unaffiliated_user_accounts, @business)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb, @business)
      assert @business.business_user_account_for(@member1).present?
      assert @org1.member?(@member1)
      assert @business.remove_members_who_are_only_members_of_these_orgs([@member1.id], [@org1.id])
      refute @business.business_user_account_for(@member1).present?
    end

    test "does not remove a member if they are not only a member of the provided orgs" do
      disable_feature_flag(:unaffiliated_user_accounts, @business)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb, @business)
      assert @business.business_user_account_for(@member1).present?
      assert @org1.member?(@member1)
      @org2.add_member(@member1)
      refute @business.remove_members_who_are_only_members_of_these_orgs([@member1.id], [@org1.id])
      assert @business.business_user_account_for(@member1).present?
    end

    test "does not remove a member if they are not a member of the provided orgs" do
      disable_feature_flag(:unaffiliated_user_accounts, @business)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb, @business)
      assert @business.business_user_account_for(@member1).present?
      assert @org1.member?(@member1)
      refute @business.remove_members_who_are_only_members_of_these_orgs([@member1.id], [@org2.id])
      assert @business.business_user_account_for(@member1).present?
    end
  end unless GitHub.single_business_environment?

  context "#remove_abilities_from_business" do
    test "removes given abilities from the business immediately" do
      assert @org1.member?(@member1)
      abilities = Ability.where(subject_type: "Organization", subject_id: @business.organization_ids, actor_type: "User", actor_id: @member1.id)
      @business.remove_abilities_from_business(abilities, actor: @owner)

      refute @org1.member?(@member1)
    end

    test "does not remove abilities not passed in" do
      @org2.add_member(@member1)
      abilities = Ability.where(subject_type: "Organization", subject_id: @org1.id, actor_type: "User", actor_id: @member1.id)
      @business.remove_abilities_from_business(abilities, actor: @owner)

      refute @org1.member?(@member1)
      assert @org2.member?(@member1)
    end

    test "does not remove abilities not belonging to the business", skip_enterprise: true do
      new_org = create :organization
      new_org.add_member(@member1)

      abilities = Ability.where(subject_type: "Organization", subject_id: new_org.id, actor_type: "User", actor_id: @member1.id)
      @business.remove_abilities_from_business(abilities, actor: @owner)
      assert new_org.member?(@member1)
    end

    test "revokes programmatic access immediately" do
      org_pat = make_user_programmatic_access_with_grant(requester: @member1, target: @org1)

      abilities = Ability.where(subject_type: "Organization", subject_id: @org1.id, actor_type: "User", actor_id: @member1.id)
      @business.remove_abilities_from_business(abilities, actor: @owner)

      assert_empty org_pat.organization_programmatic_access_grants
    end

    test "does not revoke programmatic access for other orgs" do
      @org2.add_member(@member1)
      org_pat = make_user_programmatic_access_with_grant(requester: @member1, target: @org2)

      abilities = Ability.where(subject_type: "Organization", subject_id: @org1.id, actor_type: "User", actor_id: @member1.id)
      @business.remove_abilities_from_business(abilities, actor: @owner)

      refute_empty org_pat.organization_programmatic_access_grants
    end

    test "enqueues OrganizationBulkRemoveMembersCleanupJob to perform remaining work" do
      abilities = Ability.where(subject_type: "Organization", subject_id: @org1.id, actor_type: "User", actor_id: @member1.id)

      assert_enqueued_jobs 1, only: OrganizationBulkRemoveMembersCleanupJob do
        @business.remove_abilities_from_business(abilities, actor: @owner)
      end
    end
  end

  context "#prerelease_agreement" do
    test "can have a prerelease_agreement" do
      PrereleaseProgramMember.create member: @business, actor: @owner
      refute_nil @business.prerelease_agreement
      assert_equal "Business", @business.prerelease_agreement.member_type
    end
  end

  context "instrumentation" do
    test "instruments creation" do
      events = assert_performed_audit_entries(count: 1, only: "business.create") do
        create :business
      end
      business = T.must(Business.last)
      assert_equal last_performed_audit_entries, events
      expected_payload = {
        business_id: business.id,
        business: business.slug,
        name: business.name,
      }
      assert_subset_hash expected_payload, events.first
    end unless GitHub.single_business_environment?

    test "instruments adding an organization" do
      org = create :organization

      events = assert_performed_audit_entries(count: 1, only: "business.add_organization") do
        @business.add_organization org
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        org: org.login,
        org_id: org.id,
        organization_upgrade: false,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "instruments removing an organization" do
      org = create :organization
      @business.add_organization org

      events = assert_performed_audit_entries(count: 1, only: "business.remove_organization") do
        @business.remove_organization org
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        org: org.login,
        org_id: org.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    if GitHub.billing_enabled?
      test "instruments billing type change on removing an organization when billing type changes" do
        assert_equal User::BillingDependency::INVOICE_BILLING_TYPE, @org1.billing_type

        events = assert_performed_audit_entries(count: 1, only: "billing.change_billing_type") do
          @business.remove_organization @org1, actor: @owner
        end

        assert_equal User::BillingDependency::CARD_BILLING_TYPE, @org1.reload.billing_type
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          old_billing_type: User::BillingDependency::INVOICE_BILLING_TYPE,
          billing_type: User::BillingDependency::CARD_BILLING_TYPE,
          user: @org1.login,
          user_id: @org1.id,
          actor: @owner.login,
          actor_id: @owner.id
        }
        assert_subset_hash expected_payload, events.first
      end

      test "does not instrument billing type change on removing an organization when billing type hasn't changed" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, organizations: [org], owners: [@owner])
        assert_equal User::BillingDependency::CARD_BILLING_TYPE, org.reload.billing_type

        events = assert_performed_audit_entries(count: 0, only: "billing.change_billing_type") do
          business.remove_organization org, actor: @owner
        end

        assert_equal User::BillingDependency::CARD_BILLING_TYPE, org.reload.billing_type
        assert_equal last_performed_audit_entries, events
      end

      test "instruments plan change on removing an organization" do
        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.remove_organization @org1, actor: @owner
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          old_plan: GitHub::Plan::BUSINESS_PLUS,
          plan: GitHub::Plan::FREE,
          old_plan_duration: User::BillingDependency::YEARLY_PLAN,
          plan_duration: User::BillingDependency::MONTHLY_PLAN,
          actor: @owner.login,
          actor_id: @owner.id
        }
        assert_subset_hash expected_payload, events.first
      end

      test "instruments billing email change" do
        old_email = @business.billing_email
        new_email = "new@example.com"

        events = assert_performed_audit_entries(count: 1, only: "billing.change_email") do
          @business.update! billing_email: new_email
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          email: new_email,
          old_email: old_email,
          business_id: @business.id,
          business: @business.slug,
        }
        assert_subset_hash expected_payload, events.first
      end
    end

    test "instruments adding an owner" do
      user = create :user

      events = assert_performed_audit_entries(count: 1, only: "business.add_admin") do
        @business.add_owner user, actor: @owner
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        actor: @owner.login,
        actor_id: @owner.id,
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        user: user.login,
        user_id: user.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "logs billing_term_ends_at=" do
      new_billing_term_ends_at = GitHub::Billing.today - 1.day
      expected_log = {
        "Body" => "Setting billing_term_ends_at",
        "code.namespace" => "Business",
        "code.function" => "billing_term_ends_at=",
        "gh.business.id" => @business.id,
        "gh.business.slug" => @business.slug,
        "gh.billing.billing_term_ends_at.new" => new_billing_term_ends_at
      }
      assert_logged(**expected_log) do
        @business.billing_term_ends_at = new_billing_term_ends_at
      end
    end

    test "hides staff information when adding an owner", skip_enterprise: true do
      user = create :user
      staff = create :staff_admin_user

      events = assert_performed_audit_entries(count: 1, only: "business.add_admin") do
        @business.add_owner user, actor: staff, staff_action: true
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        staff_actor: staff.display_login,
        staff_actor_id: staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        user: user.login,
        user_id: user.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "instruments removing an owner" do
      user = create :user
      @business.add_owner user, actor: @owner

      events = assert_performed_audit_entries(count: 1, only: "business.remove_admin") do
        @business.remove_owner user, actor: @owner, reason: "Reasons"
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        actor: @owner.login,
        actor_id: @owner.id,
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        user: user.login,
        user_id: user.id,
        reason: "Reasons",
      }
      assert_subset_hash expected_payload, events.first
    end

    test "an error is raised when attempting to remove the emu first owner as an enterprise owner" do
      emu = create :emu, :owner
      emu_business = emu.enterprise_managed_business
      first_owner = emu_business.find_first_emu_owner
      assert_predicate first_owner, :is_first_emu_owner?

      assert_raises_with_message(Business::ManagedUserDependency::CannotRemoveFirstEmuOwnerError, "First EMU owners cannot be removed") do
        emu_business.remove_owner(first_owner, actor: emu)
      end
    end unless GitHub.single_business_environment?

    unless GitHub.single_business_environment?
      test "instruments soft-delete" do
        events = assert_performed_audit_entries(count: 1, only: "business.delete") do
          @deletable_business.soft_delete!
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: @deletable_business.id,
          business: @deletable_business.slug,
          name: @deletable_business.name,
          owner_ids: @deletable_business.owners.map(&:id),
          owners: @deletable_business.owners.map(&:login),
        }
        assert_subset_hash expected_payload, events.first
      end

      test "instruments soft-delete with actor and self_serve arguments" do
        events = assert_performed_audit_entries(count: 1, only: "business.delete") do
          @deletable_business.soft_delete!(actor: @owner, self_serve: true)
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: @deletable_business.id,
          business: @deletable_business.slug,
          name: @deletable_business.name,
          actor: @owner.login,
          actor_id: @owner.id,
          owner_ids: @deletable_business.owners.map(&:id),
          owners: @deletable_business.owners.map(&:login),
        }
        assert_subset_hash expected_payload, events.first
      end

      test "instruments restore" do
        @deletable_business.soft_delete!
        events = assert_performed_audit_entries(count: 1, only: "business.restore") do
          @deletable_business.restore!
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: @deletable_business.id,
          business: @deletable_business.slug,
          name: @deletable_business.name,
        }
        assert_subset_hash expected_payload, events.first
      end
    end

    test "instruments destroy" do
      events = assert_performed_audit_entries(count: 1, only: "business.destroy") do
        @business.destroy
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        business_id: @business.id,
        business: @business.slug,
        name: @business.name,
        owner_ids: @business.owners.map(&:id),
        owners: @business.owners.map(&:login),
      }
      assert_subset_hash expected_payload, events.first
    end

    unless GitHub.single_business_environment?
      test "does not instrument terms of service acceptance on creation of non-trial enterprise" do
        business = build :business

        assert_performed_audit_entries(count: 0, only: "business.accept_terms_of_service") do
          business.save!
        end
      end

      test "instruments terms of service acceptance on creation of trial enterprise" do
        business = build :business, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now

        events = assert_performed_audit_entries(count: 1, only: "business.accept_terms_of_service") do
          business.save!
        end

        expected_payload = {
          business_id: business.id,
          business: business.slug,
          name: business.name,
          tos_type: "Corporate"
        }

        assert_subset_hash expected_payload, events.first
      end

      test "does not instrument terms of service change when nothing changes" do
        events = assert_performed_audit_entries(count: 0, only: "business.update_terms_of_service") do
          @business.update \
            name: "New business name",
            billing_term_ends_at: "2015-01-01"
        end
        assert events.empty?
      end

      test "instruments terms of service change on create" do
        business = build :business,
          terms_of_service_notes: "Very important notes",
          terms_of_service_company_name: "Acme, Inc"

        events = assert_performed_audit_entries(count: 1, only: "business.update_terms_of_service") do
          business.save!
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: business.id,
          business: business.slug,
          name: business.name,
          terms_of_service_type: {
            old_value: "Corporate", # Default valud is "Corporate"
            new_value: business.terms_of_service_type,
          },
          terms_of_service_notes: {
            old_value: nil,
            new_value: business.terms_of_service_notes,
          },
          terms_of_service_company_name: {
            old_value: nil,
            new_value: business.terms_of_service_company_name,
          },
        }
        assert_subset_hash expected_payload, events.first
      end

      test "instruments terms of service change on update" do
        old_type = @business.terms_of_service_type.dup
        old_notes = @business.terms_of_service_notes.dup
        old_company_name = @business.terms_of_service_company_name.dup

        events = assert_performed_audit_entries(count: 1, only: "business.update_terms_of_service") do
          @business.update \
            terms_of_service_type: "Custom",
            terms_of_service_notes: "Very important notes",
            terms_of_service_company_name: "Acme, Inc"
        end
        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: @business.id,
          business: @business.slug,
          name: @business.name,
          terms_of_service_type: {
            old_value: old_type,
            new_value: @business.terms_of_service_type,
          },
          terms_of_service_notes: {
            old_value: old_notes,
            new_value: @business.terms_of_service_notes,
          },
          terms_of_service_company_name: {
            old_value: old_company_name,
            new_value: @business.terms_of_service_company_name,
          },
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end

  context "#sync_enterprise_license" do
    if GitHub.single_business_environment?
      test "syncs license values to business when GitHub.single_business_environment?" do
        name = @business.name.dup

        license = GitHub::Enterprise::LicenseMock.new \
          expire_at: 1.year.from_now.to_datetime,
          seats: 1000,
          perpetual: false,
          unlimited: false,
          evaluation: false,
          company: Faker::Beer.name
        result = @business.sync_enterprise_license license
        assert result
        refute_nil GitHub.global_business
        assert_equal name, GitHub.global_business.name # Name is not synced
        assert_equal license.expire_at.utc.to_date, GitHub.global_business.billing_term_ends_on
        assert_equal license.seats, GitHub.global_business.seats
      end

      test "returns false when sync fails due to invalid license data" do

        license = GitHub::Enterprise::LicenseMock.new \
          expire_at: 1.year.from_now.to_datetime,
          seats: -1000, # Negative value for seats triggers a validation error
          company: Faker::Beer.name
        result = @business.sync_enterprise_license license
        refute result
      end
    else
      test "is a no-op unless GitHub.single_business_environment?" do
        name = @business.name.dup

        license = GitHub::Enterprise::LicenseMock.new \
          expire_at: 1.year.from_now.to_datetime,
          seats: 1000,
          perpetual: false,
          unlimited: false,
          evaluation: false,
          company: Faker::Beer.name
        result = @business.sync_enterprise_license license
        assert_nil result
        assert_nil GitHub.global_business
        assert_equal name, @business.name
      end
    end
  end

  context "#outside_collaborators" do
    if GitHub.single_business_environment?
      test "does not include collaborators who are suspended in single business environment" do
        user = create :user
        repo = create :repository, :minimal, owner: @org2
        repo.add_member(user)
        user.suspend("Reasons")

        refute_includes @business.outside_collaborators, user
      end
    else
      test "pending collaborators are not returned" do
        repo = create :repository, :minimal, owner: @org1

        assert RepositoryInvitation.invite_to_repo(@user, @org1.admins.first, repo)[:success], "@user not invited successfully"
        assert_same_elements [@collaborator, @collaborator2], @business.outside_collaborators
      end

      test "includes collaborators who are suspended in multi business environment" do
        user = create :user
        repo = create :repository, :minimal, owner: @org2
        repo.add_member(user)
        user.suspend("Reasons")

        assert_same_elements [user, @collaborator, @collaborator2], @business.outside_collaborators
      end

      test "collaborators who are members of the repo's organization are returned" do
        other_member = create(:user)
        @org1.add_member(other_member)

        repo = create :repository, :minimal, owner: @org1
        repo.add_member(@user)

        assert_same_elements [@user, @collaborator, @collaborator2], @business.outside_collaborators
      end

      test "collaborators who are members of other organizations in the business are returned" do
        @org1.add_member(@user)
        repo = create :repository, :minimal, owner: @org2
        repo.add_member(@user)

        assert_same_elements [@user, @collaborator, @collaborator2], @business.outside_collaborators
      end

      test "collaborators on forks of private organization repos can be included in results" do
        @org1.add_member(@forker)
        repo = create(:private_repository, owner: @org1)
        forked_repo, reason = repo.fork(forker: @forker)
        forked_repo.add_member(@user)

        assert_includes @business.outside_collaborators(include_forks: true), @user
      end

      test "collaborators on forks of private organization repos can be excluded from results" do
        @org1.add_member(@forker)
        repo = create(:private_repository, owner: @org1)
        forked_repo, reason = repo.fork(forker: @forker)
        forked_repo.add_member(@user)

        refute_includes @business.outside_collaborators(include_forks: false), @user
      end

      test "collaborators can be filtered by org name if the query string is an exact match" do
        assert_same_elements [@collaborator], @business.outside_collaborators(organization_ids: [@org1.id])
        assert_same_elements [@collaborator2], @business.outside_collaborators(organization_ids: [@org2.id])
      end
    end
  end

  context "#outside_collaborator_ids" do
    test "filtering outside collaborators by organization works" do
      outside_collaborator1 = create :user, login: "outside-collaborator1"
      outside_collaborator2 = create :user, login: "outside-collaborator2"
      outside_collaborator3 = create :user, login: "outside-collaborator3"
      repo1 = create :repository, :minimal, owner: @org1, name: "my_repo1"
      repo1.add_member(outside_collaborator1)
      repo2 = create :repository, :minimal, owner: @org2, name: "my_repo2"
      repo2.add_member(outside_collaborator2)
      repo2.add_member(outside_collaborator3)

      assert_same_elements [@collaborator.id, outside_collaborator1.id], @business.outside_collaborator_ids(organization_ids_filter: [@org1.id])
      assert_same_elements [@collaborator2.id, outside_collaborator2.id, outside_collaborator3.id], @business.outside_collaborator_ids(organization_ids_filter: [@org2.id])
    end

    test "filter outside collaborators by an organization that a collaborator belongs to, but which they are not an outside collaborator on, does not return anything" do
      random_org = create :organization
      random_org.add_member(@collaborator)

      assert_empty @business.outside_collaborator_ids(organization_ids_filter: [random_org.id])
    end

    test "filtering by collaborators that have 2FA enabled works" do
      user_2fa_enabled = create :two_factor_credential_user, login: "user-2fa-enabled"
      @org1.add_member(user_2fa_enabled)
      repo = create :repository, :minimal, owner: @org2
      repo.add_member(user_2fa_enabled)

      assert user_2fa_enabled.two_factor_authentication_enabled?
      refute @collaborator.two_factor_authentication_enabled?, @collaborator2.two_factor_authentication_enabled?

      assert_same_elements [user_2fa_enabled], @business.outside_collaborators(with_two_factor_status: :enabled)
    end

    test "filtering by collaborators that have 2FA disabled works" do
      user_2fa_enabled = create :two_factor_credential_user, login: "user-2fa-enabled"
      @org1.add_member(user_2fa_enabled)
      repo = create :repository, :minimal, owner: @org2
      repo.add_member(user_2fa_enabled)

      assert user_2fa_enabled.two_factor_authentication_enabled?
      refute @collaborator.two_factor_authentication_enabled?, @collaborator2.two_factor_authentication_enabled?

      assert_same_elements [@collaborator, @collaborator2], @business.outside_collaborators(with_two_factor_status: :disabled)
    end

    test "filters out collaborators on advisory workspace repos" do
      perform_enqueued_jobs(only: [WorkspaceAbilitySetupJob]) do
        # Create a draft repo advisory on a _public_ repo, and create a
        # _private_ workspace repo for it
        advisory = create(:draft_repository_advisory, :with_workspace,
                          repository: @repo1)

        # Add an external user as a collaborator on the advisory, which also
        # grants write ability on the private workspace repo (Note advisory
        # collaborator is different than repo collaborator)
        advisory.add_collaborator(@user)
        repo_invitation = RepositoryInvitation.find_by(invitee_id: @user.id, repository_id: advisory.workspace_repository.id)
        repo_invitation&.accept!(acceptor: @user)

        # Verify workspace repo is private and writable by the external user
        assert advisory.readable_by?(@user)
        refute_nil advisory.workspace_repository
        assert advisory.workspace_repository.private?
        assert advisory.workspace_repository.writable_by?(@user)

        # Verify workspace collaborator _is not_ counted as an outside user
        outside_collaborator_ids = @business.outside_collaborator_ids
        refute_includes outside_collaborator_ids, @user.id
      end
    end

    test "uses cached ids when collaborator_cache_read FF is enabled" do
      enable_feature_flag(:collaborator_cache_read)
      OrganizationCollaborator.destroy_all
      outside_collaborator = create(:user)
      OrganizationCollaborator.create(user_id: outside_collaborator.id, business_id: @business.id, organization_id: @org1.id, private: true)
      assert_equal [outside_collaborator.id], @business.outside_collaborator_ids
      assert_equal [outside_collaborator.id], @business.outside_collaborator_ids(on_repositories_with_visibility: [:private])
      assert_equal [outside_collaborator.id], @business.outside_collaborator_ids(on_repositories_with_visibility: [:private], organization_ids_filter: [@org1.id])
      assert_equal [], @business.outside_collaborator_ids(on_repositories_with_visibility: [:private], organization_ids_filter: [@org2.id])
      assert_equal [], @business.outside_collaborator_ids(on_repositories_with_visibility: [:public])
    end

    test "uses experiment for cached ids when collaborator_cache_write FF is enabled and collaborator_cache_read FF is disabled" do
      enable_feature_flag(:collaborator_cache_write)
      disable_feature_flag(:collaborator_cache_read)
      OrganizationCollaborator.destroy_all
      outside_collaborator = create(:user)
      OrganizationCollaborator.create(user_id: outside_collaborator.id, business_id: @business.id, organization_id: @org1.id, private: true)
      assert_raises Scientist::Experiment::MismatchError do
        @business.outside_collaborator_ids
      end
    end
  end

  context "#visible_organization_members_for" do
    test "returns visible org members to a business member" do
      assert_same_elements \
        [@member1, @public_member_of_org2] + @org1.admins,
        @business.visible_organization_members_for(@member1).to_a
    end

    test "returns visible org members to a business member, for subset of orgs" do
      assert_same_elements \
        [@member1] + @org1.admins,
        @business.visible_organization_members_for(@member1, org_ids: [@org1.id]).to_a
    end

    if GitHub.single_business_environment?
      test "returns all memberships ignoring visibility for a business admin" do
        assert_same_elements \
          @business.single_business_members,
          @business.visible_organization_members_for(@owner).to_a
      end
    else
      test "returns all memberships ignoring visibility for a business admin" do
        assert_same_elements \
          [@member1, @member2, @public_member_of_org2] + @org1.admins + @org2.admins,
          @business.visible_organization_members_for(@owner).to_a
      end

      test "returns all memberships ignoring visibility with ignore_visibility: true" do
        assert_same_elements \
          [@member1, @member2, @public_member_of_org2] + @org1.admins + @org2.admins,
          @business.visible_organization_members_for(@member1, ignore_visibility: true).to_a
      end
    end
  end

  context "#flipper_id" do
    test "is the business id" do
      assert_equal "Business:#{@business.id}", @business.flipper_id
    end
  end

  context "#member?" do
    test "returns true for business admins" do
      assert @business.member?(@owner)
    end

    test "returns true for organization members" do
      assert @business.member?(@org1.admins.first)
    end

    test "returns false for non-business members" do
      refute @business.member?(@user)
    end

    test "returns false if user is not a user" do
      refute @business.member?(@org1)
    end

    test "returns false if user is nil" do
      refute @business.member?(nil)
    end
  end

  context "#async_member?" do
    test "resolves to true for business admins" do
      assert @business.async_member?(@owner).sync
    end

    test "resolves to true for organization members" do
      assert @business.async_member?(@org1.admins.first).sync
    end

    test "resolves to false for non-business members" do
      refute @business.async_member?(@user).sync
    end

    test "resolves to false if user is not a user" do
      refute @business.async_member?(@org1).sync
    end

    test "resolves to false if user is nil" do
      refute @business.async_member?(nil).sync
    end
  end

  context "#single_business_members" do
    if GitHub.single_business_environment?
      test "returns all active users on the installation" do
        orphan = create :user, login: "orphan"

        single_business_members = [
          orphan, @owner, @billing_manager, @user, @member1, @member2,
          @public_member_of_org2, @collaborator, @collaborator2, @forker
        ].concat(@org1.admins).concat(@org2.admins)
        assert_same_elements single_business_members, @business.single_business_members
      end
    else
      test "returns an empty array unless in a single business environment" do
        assert_equal [], @business.single_business_members
      end
    end
  end

  context "#user_is_member_of_owned_org?" do
    test "returns true for member of an owned org" do
      assert @business.user_is_member_of_owned_org?(@member1)
    end

    test "returns true for owner of an owned org" do
      assert @business.user_is_member_of_owned_org?(@org1.admins.first)
    end

    test "returns false for enterprise owner that is not a member of any owned orgs" do
      refute @business.user_is_member_of_owned_org?(@owner)
    end

    test "returns false for enterprise billing manager that is not a member of any owned orgs" do
      refute @business.user_is_member_of_owned_org?(@billing_manager)
    end

    test "returns false for someone else that is not a member of any owned orgs" do
      refute @business.user_is_member_of_owned_org?(create(:user))
    end
  end

  context "#user_is_owner_of_owned_org?" do
    test "returns true for owner of an owned org" do
      assert @business.user_is_owner_of_owned_org?(@org1.admins.first)
    end

    test "returns false for member of an owned org" do
      refute @business.user_is_owner_of_owned_org?(@member1)
    end

    test "returns false for enterprise owner that is not a member of any owned orgs" do
      refute @business.user_is_owner_of_owned_org?(@owner)
    end

    test "returns false for enterprise billing manager that is not a member of any owned orgs" do
      refute @business.user_is_owner_of_owned_org?(@billing_manager)
    end

    test "returns false for a user that has no role in any owned orgs" do
      refute @business.user_is_owner_of_owned_org?(create(:user))
    end
  end

  context "#readable_by?" do
    test "is true for business admins" do
      assert @business.readable_by?(@owner)
    end

    test "is true for business billing managers" do
      assert @business.readable_by?(@billing_manager)
    end

    test "is true for invited business admins" do
      create :business_administrator_invitation, role: :owner, \
        business: @business, inviter: @owner, invitee: @user
      assert @business.readable_by?(@user)
    end

    test "is true for invited business billing managers" do
      create :business_administrator_invitation, role: :billing_manager, \
        business: @business, inviter: @owner, invitee: @user
      assert @business.readable_by?(@user)
    end

    test "is true for org admins" do
      assert @business.readable_by?(@org1.admins.first)
    end

    test "is true for org members" do
      assert @business.readable_by?(@member1)
    end

    test "is true for admins of organizations invited to the business" do
      invite = create :business_organization_invitation,
        business: @business, inviter: @owner
      invited_org = invite.invitee
      assert @business.readable_by?(invited_org.admins.first)
    end

    test "is true for bots of integrations owned by the business" do
      integration = create :enterprise_owned_integration, owner: @business
      bot = integration.bot
      assert @business.readable_by?(bot)
    end

    test "is false for members of organizations invited to the business" do
      invite = create :business_organization_invitation,
        business: @business, inviter: @owner
      invited_org = invite.invitee
      invited_org.add_member(@user)
      refute @business.readable_by?(@user)
    end

    test "is true if the user has a removed member notification" do
      notification = Business::RemovedMemberNotification.new(@business, @user)
      notification.add_two_factor_requirement_non_compliance

      assert @business.readable_by?(@user)
    end

    test "is false for random users" do
      refute @business.readable_by?(@user)
    end

    test "is false for nil users" do
      refute @business.readable_by?(nil)
    end
  end

  context "#saml_members" do
    test "returns business admins, organization members, and billing managers" do
      assert_same_elements [@owner, @billing_manager, @member1, @member2, @public_member_of_org2, @org1.admin, @org2.admin], @business.saml_members
    end

    test "does not return outside collaborators" do
      refute_includes [@collaborator, @collaborator2], @business.saml_members
    end

    test "does not return pending members or admins" do
      pending_member = create :user
      pending_admin = create :user
      @org1.invite(pending_member, inviter: @org1.admin)
      @business.invite_admin(user: pending_admin, inviter: @owner, role: :owner)

      assert_includes @org1.pending_members, pending_member
      assert_includes @business.invitations.map(&:invitee), pending_admin
      refute_includes [pending_member, pending_admin], @business.saml_members
    end
  end

  context "#external_members" do
    test "returns business admins, organization members, and billing managers" do
      assert_same_elements [@owner, @billing_manager, @member1, @member2, @public_member_of_org2, @org1.admin, @org2.admin], @business.external_members
    end

    test "does not return outside collaborators" do
      refute_includes [@collaborator, @collaborator2], @business.external_members
    end

    test "does not return pending members or admins" do
      pending_member = create :user
      pending_admin = create :user
      @org1.invite(pending_member, inviter: @org1.admin)
      @business.invite_admin(user: pending_admin, inviter: @owner, role: :owner)

      assert_includes @org1.pending_members, pending_member
      assert_includes @business.invitations.map(&:invitee), pending_admin
      refute_includes [pending_member, pending_admin], @business.external_members
    end
  end

  context "#integration_installations" do
    test "returns IntegrationInstallations targeting the business" do
      assert_same_elements [@integration_installation], @business.integration_installations
    end
  end

  context "#integrations" do
    test "returns integrations owned by the Business" do
      assert_same_elements [@integration], @business.reload.integrations
    end
  end

  context "#create_user_accounts_for_members" do
    if GitHub.single_business_environment?
      test "does not create business user accounts for business members if it is a single business environment" do
        Business.delete_all
        business = create :business

        assert_equal 0, business.user_accounts.count
      end
    else
      test "creates business user accounts for all seated members and admins if not a single business environment" do
        assert_equal 8, @business.user_accounts.count
      end
    end
  end

  context "#remove_business_user_accounts_for_members" do
    test "removes business user accounts for all business members and admins" do
      @business.destroy
      assert_equal 0, @business.user_accounts.count
    end
  end unless GitHub.single_business_environment?

  context "#enterprise_installations" do
    test "returns enterprise installations owned by the business" do
      installation = create :enterprise_installation, owner: @business
      assert_same_elements [@enterprise_installation, installation], @business.reload.enterprise_installations
    end
  end

  context "#ip_allowlist_entries" do
    test "returns IP allow list entries owned by the business" do
      entry = create :ip_allowlist_entry, owner: @business
      assert_same_elements [entry], @business.reload.ip_allowlist_entries
    end
  end

  context "#filtered_ip_allowlist_entries" do
    test "returns filtered IP allow list entries owned by the business" do
      matching = create :ip_allowlist_entry, owner: @business, allow_list_value: "1.2.3.4"
      not_matching = create :ip_allowlist_entry, owner: @business, allow_list_value: "4.3.2.1"
      assert_same_elements [matching], @business.filtered_ip_allowlist_entries(query: "1.2")
    end
  end

  context "#filtered_installed_app_ip_allowlist_entries" do
    test "returns filtered IP allow list entries for apps installed on the business" do
      matching = create :ip_allowlist_entry, owner: @integration, allow_list_value: "1.2.3.4"
      not_matching = create :ip_allowlist_entry, owner: @integration, allow_list_value: "4.3.2.1"
      assert_same_elements [matching], @business.filtered_installed_app_ip_allowlist_entries(query: "1.2")
    end
  end

  context "#staff_notes" do
    test "returns existing StaffNotes for the Business" do
      note = create :staff_note, notable: @business
      assert_same_elements [note], @business.staff_notes
    end
  end

  context "#team_sync_enabled?" do
    test "false if there is no tenant" do
      refute_predicate @business, :team_sync_enabled?
    end

    test "false if the tenant doesn't have 'enabled' status" do
      create :business_team_sync_tenant, business: @business, status: "pending"
      refute_predicate @business, :team_sync_enabled?
    end

    test "true if the tenant has the 'enabled' status" do
      create :business_team_sync_tenant, business: @business, status: "enabled"
      assert_predicate @business, :team_sync_enabled?
    end
  end

  context "#admin_and_organization_member_ids" do
    test "returns org members, billing managers, and business admins by default" do
      billing_manager = create :user
      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
        @owner.id,
        @billing_manager.id,
        billing_manager.id,
      ]

      @org1.billing.add_manager(billing_manager, actor: @org1.admins.first)

      results = @business.reload.admin_and_organization_member_ids
      assert_same_elements expected_results, results
    end

    test "does not include org billing managers when opted out" do
      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
        @owner.id,
        @billing_manager.id,
      ]

      org_billing_manager = create :user
      @org1.billing.add_manager(org_billing_manager, actor: @org1.admins.first)

      results = @business.reload.admin_and_organization_member_ids(include_org_billing_managers: false)
      assert_same_elements expected_results, results
    end

    test "includes a user only once if they show up in more than category" do
      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
        @owner.id,
        @billing_manager.id,
      ]

      assert_same_elements expected_results, @business.reload.admin_and_organization_member_ids
    end
  end

  context "#business_org_abilities" do
    test "returns abilities with block on experiment" do
      enable_feature_flag(:run_business_org_abilities_experiment)
      disable_feature_flag(:batch_business_org_abilities)

      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
      ]

      abilities = @business.reload.business_org_abilities do |scope|
        scope.pluck(:actor_id)
      end

      assert_same_elements expected_results, abilities
    end

    test "returns abilities without block on experiment" do
      enable_feature_flag(:run_business_org_abilities_experiment)
      disable_feature_flag(:batch_business_org_abilities)

      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
      ]

      assert_same_elements expected_results, @business.reload.business_org_abilities.pluck(:actor_id).uniq
    end
  end

  context "#organization_member_ids" do
    test "returns org members, and org admins by default" do
      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @member2.id,
        @org2.admins.first.id,
        @public_member_of_org2.id,
      ]

      assert_same_elements expected_results, @business.reload.organization_member_ids
    end

    test "filters by actor_ids over batch limit" do
      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @public_member_of_org2.id,
      ]

      Business.stub_const(:FETCH_BATCH_SIZE, 2) do
        assert_same_elements expected_results, @business.reload.organization_member_ids(actor_ids: [@org1.admins.first.id, @member1.id, @public_member_of_org2.id])
      end
    end

    test "filters by actor_ids below batch limit" do
      @org2.add_member(@member1)
      @org1.billing.add_manager(@billing_manager, actor: @org1.admins.first)
      @business.add_owner(@member2, actor: @business.owners.first)

      expected_results = [
        @member1.id,
        @org1.admins.first.id,
        @public_member_of_org2.id,
      ]

      Business.stub_const(:FETCH_BATCH_SIZE, 5) do
        assert_same_elements expected_results, @business.reload.organization_member_ids(actor_ids: [@org1.admins.first.id, @member1.id, @public_member_of_org2.id])
      end
    end

    test "filters by org_ids over batch limit" do
      org3, org4, org5 = create(:organization, business: @business), create(:organization, business: @business), create(:organization, business: @business)
      member3, member4, member5 = create(:user), create(:user), create(:user)
      org3.add_member(member3)
      org4.add_member(member4)
      org5.add_member(member5)

      expected_results = [
        member3.id,
        member4.id,
        member5.id,
        org3.admins.first.id,
        org4.admins.first.id,
        org5.admins.first.id,
      ]

      Business.stub_const(:FETCH_BATCH_SIZE, 2) do
        assert_same_elements expected_results, @business.reload.organization_member_ids(org_ids: [org3.id, org4.id, org5.id])
      end
    end

    test "filters by org_ids below batch limit" do
      org3, org4, org5 = create(:organization, business: @business), create(:organization, business: @business), create(:organization, business: @business)
      member3, member4, member5 = create(:user), create(:user), create(:user)
      org3.add_member(member3)
      org4.add_member(member4)
      org5.add_member(member5)

      expected_results = [
        member3.id,
        member4.id,
        member5.id,
        org3.admins.first.id,
        org4.admins.first.id,
        org5.admins.first.id,
      ]

      Business.stub_const(:FETCH_BATCH_SIZE, 5) do
        assert_same_elements expected_results, @business.reload.organization_member_ids(org_ids: [org3.id, org4.id, org5.id])
      end
    end
  end

  context "#organization_logins_for_member" do
    test "returns display logins for all orgs a member belongs to" do
      assert_equal [@org1.display_login], @business.organization_logins_for_member(@member1)
      # the underlying Hash is memoized, but contains results for all users, since the
      # call above did not pass in a member_ids param
      assert_equal [@org2.display_login], @business.organization_logins_for_member(@member2)
    end

    test "returns empty array if member doesn't belong to any orgs" do
      assert_empty @business.reload.organization_logins_for_member(@owner)
    end

    test "can limit results to just the passed in array of members" do
      assert_equal [@org1.display_login],
        @business.organization_logins_for_member(@member1, member_ids: [@member1.id])

      @business.expects(:business_org_abilities).never
      @business.expects(:organizations_hash).never
      # the underlying Hash is memoized, and does not contain results for @member2, since the
      # call above passed in member_ids param set to just [@member1.id]
      assert_empty @business.organization_logins_for_member(@member2)
    end

    test "memoizes the results" do
      expected_result = [@org1.display_login]
      assert_equal expected_result, @business.organization_logins_for_member(@member1)

      org_new = create(:organization)
      org_new.add_member(@member1)
      @business.add_organization(org_new)
      @business.reload
      assert_equal expected_result, @business.organization_logins_for_member(@member1)

      updated_result = [@org1.display_login, org_new.display_login]
      reloaded_business = Business.find_by(id: @business.id)
      assert_same_elements updated_result, T.must(reloaded_business).organization_logins_for_member(@member1)
    end
  end

  context "#supports_internal_repositories?" do
    test "always returns true" do
      assert_predicate @business, :supports_internal_repositories?
    end
  end

  unless GitHub.single_business_environment?
    context "#add_user_accounts" do
      test "adds only unique members that are not already in the business" do
        assert_equal 8, @business.user_accounts.count

        new_org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        new_org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        new_member = create :user
        new_org1.add_member new_member
        new_org2.add_member new_member

        @business.add_user_accounts(new_org1.member_ids)
        @business.add_user_accounts(new_org2.member_ids)
        assert_equal 11, @business.user_accounts.count
      end

      test "does not add members who have a server-only user account in the business" do
        email_address = @enterprise_installation_user_account.emails.first.email
        user = create :user, :verified, email: email_address

        assert_no_difference("@business.user_accounts.count") do
          @business.add_user_accounts([user.id])
        end
        assert_equal user.id, @business_user_account.reload.user_id
      end

      test "does not match server-only users with dotcom users' un-verified email addresses" do
        email_address = @enterprise_installation_user_account.emails.first.email
        user = create :user, email: email_address

        assert_difference("@business.user_accounts.count", 1) do
          @business.add_user_accounts([user.id])
        end
        assert_nil @business_user_account.reload.user_id
      end

      test "matches server-only users with exteral-identity nameId for a buisness provider" do
        email_address = @enterprise_installation_user_account.emails.first.email
        provider = create :business_saml_provider, business: @business
        saml_user_data = Platform::Provisioning::SamlUserData.new([
          { "name" => "NameID", "value" => email_address },
        ])
        external_identity = create :external_identity, provider: provider, saml_user_data: saml_user_data
        user = external_identity.user

        assert_no_difference("@business.user_accounts.count") do
          @business.add_user_accounts([user.id])
        end
        assert_equal user.id, @business_user_account.reload.user_id
      end

      test "does not match server-only users with exteral-identity nameId for a different buisness's provider" do
        email_address = @enterprise_installation_user_account.emails.first.email
        provider = create :business_saml_provider
        saml_user_data = Platform::Provisioning::SamlUserData.new([
          { "name" => "NameID", "value" => email_address },
        ])
        external_identity = create :external_identity, provider: provider, saml_user_data: saml_user_data
        user = external_identity.user

        assert_difference "@business.user_accounts.count", 1 do
          @business.add_user_accounts([user.id])
        end
        assert_nil @business_user_account.reload.user_id
      end

      test "does not add duplicate records in the same batch" do
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 11
        user = create :user
        org.add_member user
        @business.add_user_accounts(org.member_ids + org.member_ids)
        assert_equal 10, @business.user_accounts.count
      end

      test "adds unaffiliated member" do
        user = create :user
        assert_enqueued_jobs 1, only: BusinessUserAccountUpdateAttributesJob do
          assert_difference "@business.user_accounts.count", 1 do
            @business.add_user_accounts([user.id])
          end
        end
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob

        bua = @business.business_user_account_for(user)
        assert bua.has_business_role?(:unaffiliated)
      end
    end

    context "#add_user_accounts_for_organization_members" do
      test "enqueues BusinessUserAccountCreateForOrganizationJob" do
        new_org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        new_member = create :user
        new_org.add_member new_member

        ids = Organization::LicenseAttributer.new(new_org).user_ids.to_a
        assert_enqueued_with(job: BusinessUserAccountCreateForOrganizationJob, args: [@business, new_org]) do
          @business.add_user_accounts_for_organization_members(new_org)
        end
      end

      test "adds BusinessUserAccounts for org members" do
        assert_equal 8, @business.user_accounts.count

        new_org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        new_member = create :user
        new_org.add_member new_member

        perform_enqueued_jobs only: BusinessUserAccountCreateForOrganizationJob do
          @business.add_user_accounts_for_organization_members(new_org)
        end

        assert_equal 10, @business.user_accounts.count
      end
    end

    context "#remove_users_from_business" do
      test "does not remove org member" do
        bua = @business.business_user_account_for(@member1)
        refute_nil bua
        @business.remove_users_from_business([@member1.id])
        bua = @business.business_user_account_for(@member1)
        refute_nil bua
      end

      test "removes unaffiliated member" do
        disable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        user = create :user
        @business.add_user_accounts([user.id])
        bua = @business.business_user_account_for(user)
        refute_nil bua
        @business.remove_users_from_business([user.id])
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
        bua = @business.business_user_account_for(user)
        assert_nil bua
      end

      test "removes single unaffiliated member" do
        enable_feature_flag(:batch_business_org_abilities)
        disable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        disable_feature_flag(:collaborator_cache_read)

        user = create :user
        @business.add_user_accounts([user.id])
        bua = @business.business_user_account_for(user)
        refute_nil bua
        query_count = TestEnv.test_all_features? ? 28 : 26

        assert_query_count(query_count, ignore_feature_flags: true) do
          @business.remove_users_from_business([user.id])
        end

        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
        bua = @business.business_user_account_for(user)
        assert_nil bua
      end

      test "removes unaffiliated member with force" do
        enable_feature_flag(:unaffiliated_user_accounts)
        user = create :user
        @business.add_user_accounts([user.id])
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
        bua = @business.business_user_account_for(user)
        refute_nil bua
        @business.remove_users_from_business([user.id], force: true)
        bua = @business.business_user_account_for(user)
        assert_nil bua
      end

      test "does not remove unaffiliated member without force when feature is enabled" do
        enable_feature_flag(:unaffiliated_user_accounts)
        user = create :user
        @business.add_user_accounts([user.id])
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
        bua = @business.business_user_account_for(user)
        refute_nil bua
        @business.remove_users_from_business([user.id])
        bua = @business.business_user_account_for(user)
        refute_nil bua
      end

      test "does not remove collaborators when add_collaborator_user_accounts is enabled" do
        @business.stubs(:add_collaborator_user_accounts?).returns(true)

        user = create :user
        @repo2.add_member(user, action: :write)
        @business.add_user_accounts([user.id])
        refute_nil @business.business_user_account_for(user)

        @business.remove_users_from_business([user.id])
        refute_nil @business.business_user_account_for(user)
      end

      test "removes collaborators when add_collaborator_user_accounts is disabled for non-EMU business", skip_with_all_emus: true do
        disable_feature_flag(:unaffiliated_user_accounts) # unaffiliated_user_accounts disables removing collaborators as well
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        @business.stubs(:add_collaborator_user_accounts?).returns(false)

        user = create :user
        @repo2.add_member(user, action: :write)
        @business.add_user_accounts([user.id])
        refute_nil @business.business_user_account_for(user)

        @business.remove_users_from_business([user.id])
        assert_nil @business.business_user_account_for(user)
      end

      test "does not remove unaffiliated users from EMU businesses" do
        emu_creator = create :emu, :owner
        emu_business = emu_creator.enterprise_managed_business
        unaffiliated_emu = create :emu, business: emu_business
        refute_nil emu_business.business_user_account_for(unaffiliated_emu)

        emu_business.remove_users_from_business([unaffiliated_emu.id])
        refute_nil emu_business.business_user_account_for(unaffiliated_emu)
      end

      test "makes call to destroy associated enterprise team memberships" do
        user = create :user, business: @business
        @business.add_user_accounts([user.id])
        EnterpriseTeam.expects(:destroy_memberships_for).with(business_id: @business.id, user_ids: [user.id]).once
        @business.remove_users_from_business([user.id], force: true)
      end

      test "removes internally visible Integration oauth authorizations for the users" do
        user_one = create :user
        user_two = create :user
        perform_enqueued_jobs(only: BusinessUserAccountUpdateAttributesJob) do
          @business.add_user_accounts([user_one.id, user_two.id])
        end

        integration = create :enterprise_owned_integration, owner: @business
        access_one = integration.grant(user_one)
        access_two = integration.grant(user_two)

        perform_enqueued_jobs(only: RevokeInternalAppAuthorizationsJob) do
          @business.remove_users_from_business([user_one.id, user_two.id], force: true)
        end

        assert_nil OauthAuthorization.find_by(id: access_one.id)
        assert_nil OauthAuthorization.find_by(id: access_two.id)
      end

      test "removes fine grained permissions for the users" do
        enable_feature_flag(:custom_enterprise_role_feature, @business)
        enable_feature_flag(:business_revoke_fgp_from_users, @business)

        user = create :user
        perform_enqueued_jobs(only: BusinessUserAccountUpdateAttributesJob) do
          @business.add_user_accounts([user.id])
        end

        grant_custom_enterprise_role(user: user, target: @business, fgps: [:read_enterprise_custom_enterprise_role])
        grant_custom_enterprise_role(user: user, target: @business, fgps: [:read_enterprise_custom_org_role])
        assert Authz.domain.check_allowed(user, :read_enterprise_custom_enterprise_role, @business)
        assert Authz.domain.check_allowed(user, :read_enterprise_custom_org_role, @business)

        perform_enqueued_jobs(only: RevokeEnterpriseRolesJob) do
          @business.remove_users_from_business([user.id], force: true)
        end

        refute Authz.domain.check_allowed(user, :read_enterprise_custom_enterprise_role, @business)
        refute Authz.domain.check_allowed(user, :read_enterprise_custom_org_role, @business)
      end
    end

    context "#dotcom_users_from_emails" do
      test "finds all the BusinessUserAccounts associated with Users that have the given email addresses" do
        accounts_hash = @business.dotcom_users_from_emails([@member1.email])
        business_user_account = @member1.business_user_accounts.find_by(business_id: @business.id)
        expected_hash = { @member1.email => business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end

      test "emails used as keys are always downcased" do
        email = "OCTOCAT@GITHUB.COM"
        member = create :user, email: email
        member.primary_user_email.verify!
        @org1.add_member member
        accounts_hash = @business.dotcom_users_from_emails([email])
        business_user_account = member.business_user_accounts.find_by(business_id: @business.id)
        expected_hash = { email.downcase => business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end

      test "does not return entries for verified emails for users that are not in the business" do
        email = "foo@example.com"
        member = create :user, email: email
        member.primary_user_email.verify!
        accounts_hash = @business.dotcom_users_from_emails([@member1.email, email])
        business_user_account = @member1.business_user_accounts.find_by(business_id: @business.id)
        expected_hash = { @member1.email => business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end

      test "emails are sliced" do
        email = "foo-du@example.com"
        member2 = create :user, email: email
        member2.primary_user_email.verify!
        @org1.add_member member2
        accounts_hash = @business.dotcom_users_from_emails([@member1.email, member2.email], slice_size: 1)
        business_user_account = @member1.business_user_accounts.find_by(business_id: @business.id)
        member2_user_account = member2.business_user_accounts.find_by(business_id: @business.id)
        expected_hash = { @member1.email => business_user_account, member2.email => member2_user_account }
        assert_same_hash expected_hash, accounts_hash
      end
    end

    context "#dotcom_users_from_extid_emails" do
      context "SAML business" do
        test "finds all the BusinessUserAccounts associated with users that have the given email addresses" do
          provider = create :business_saml_provider
          business = provider.business

          # Email only in NameID
          nameid_user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user1@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: nameid_user, saml_user_data: saml_user_data)

          # Email only in emails
          emails_user = create(:user, email: "user2@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user2" },
            { "name" => "emails", "value" => "user2@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: emails_user, saml_user_data: saml_user_data)

          # Email only in claims/name
          claims_user = create(:user, email: "user3@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user3" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "value" => "user3@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: claims_user, saml_user_data: saml_user_data)

          # Email only in claims/emailaddress
          claims_email_user = create(:user, email: "user4@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user4" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress", "value" => "user4@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: claims_email_user, saml_user_data: saml_user_data)

          business.add_user_accounts([nameid_user.id, emails_user.id, claims_user.id, claims_email_user.id])

          expected_hash = {
            "user1@github.com" => nameid_user.business_user_accounts.find_by(business_id: business.id),
            "user2@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
            "user3@github.com" => claims_user.business_user_accounts.find_by(business_id: business.id),
            "user4@github.com" => claims_email_user.business_user_accounts.find_by(business_id: business.id),
          }

          emails = %w[user1@github.com user2@github.com user3@github.com user4@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end

        test "sliced: finds all the BusinessUserAccounts associated with users that have the given email addresses" do
          provider = create :business_saml_provider
          business = provider.business

          # Email only in NameID
          nameid_user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user1@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: nameid_user, saml_user_data: saml_user_data)

          # Email only in emails
          emails_user = create(:user, email: "user2@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user2" },
            { "name" => "emails", "value" => "user2@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: emails_user, saml_user_data: saml_user_data)

          # Email only in claims/name
          claims_user = create(:user, email: "user3@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user3" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "value" => "user3@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: claims_user, saml_user_data: saml_user_data)

          # Email only in claims/emailaddress
          claims_email_user = create(:user, email: "user4@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user4" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress", "value" => "user4@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: claims_email_user, saml_user_data: saml_user_data)

          business.add_user_accounts([nameid_user.id, emails_user.id, claims_user.id, claims_email_user.id])

          expected_hash = {
            "user1@github.com" => nameid_user.business_user_accounts.find_by(business_id: business.id),
            "user2@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
            "user3@github.com" => claims_user.business_user_accounts.find_by(business_id: business.id),
            "user4@github.com" => claims_email_user.business_user_accounts.find_by(business_id: business.id),
          }

          emails = %w[user1@github.com user2@github.com user3@github.com user4@github.com]
          accounts_hash = assert_query_count(5) do
            business.dotcom_users_from_extid_emails(emails, slice_size: 2)
          end
          assert_same_hash expected_hash, accounts_hash
        end

        test "finds all the BusinessUserAccounts associated with users that have the given mixed-case email addresses" do
          provider = create :business_saml_provider
          business = provider.business

          # Email only in NameID
          nameid_user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "USER1@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: nameid_user, saml_user_data: saml_user_data)

          # Email only in emails
          emails_user = create(:user, email: "user2@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user2" },
            { "name" => "emails", "value" => "user2@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: emails_user, saml_user_data: saml_user_data)

          business.add_user_accounts([nameid_user.id, emails_user.id])

          expected_hash = {
            "user1@github.com" => nameid_user.business_user_accounts.find_by(business_id: business.id),
            "user2@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
          }

          emails = %w[user1@github.com USER2@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end

        test "unassigned identities are not returned" do
          provider = create :business_saml_provider
          business = provider.business

          # Create an unassigned identity
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "USER1@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: nil, saml_user_data: saml_user_data)

          assigned_user = create(:user, email: "user2@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user2@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: assigned_user, saml_user_data: saml_user_data)

          business.add_user_accounts([assigned_user.id])

          expected_hash = {
            "user2@github.com" => assigned_user.business_user_accounts.find_by(business_id: business.id),
          }

          emails = %w[user1@github.com user2@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end

        test "finds BusinessUserAccount where nameid is an email but not in emails SAML data" do
          provider = create :business_saml_provider
          business = provider.business

          nameid_user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "USER1@github.com" },
            { "name" => "emails", "value" => "foo@bar.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: nameid_user, saml_user_data: saml_user_data)

          business.add_user_accounts([nameid_user.id])

          expected_hash = {
            "user1@github.com" => nameid_user.business_user_accounts.find_by(business_id: business.id),
          }

          accounts_hash = business.dotcom_users_from_extid_emails(["USER1@github.com"])
          assert_same_hash expected_hash, accounts_hash
        end
      end

      context "SCIM business" do
        test "finds all the BusinessUserAccounts associated with users that have the given email addresses" do
          provider = create :business_saml_provider
          business = provider.business
          # Email only in emails
          emails_user = create(:user, email: "user5@example.com")
          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User5-IdP-Id" },
            { "name" => "emails", "value" => "user5@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: emails_user, scim_user_data: scim_user_data)

          # Email only in username
          username_user = create(:user, email: "user6@example.com")
          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User6-IdP-Id" },
            { "name" => "userName", "value" => "user6@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: username_user, scim_user_data: scim_user_data)

          business.add_user_accounts([emails_user.id, username_user.id])

          expected_hash = {
            "user5@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
            "user6@github.com" => username_user.business_user_accounts.find_by(business_id: business.id),
          }
          emails = %w[user5@github.com user6@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end
      end

      context "Business with SAML org" do
        test "finds all the BusinessUserAccounts associated with users that have the given email addresses" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          provider = create :organization_saml_provider, organization: org

          # Email only in NameID
          nameid_user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user1@github.com" },
          ])
          create(:external_identity, provider: provider, user: nameid_user, saml_user_data: saml_user_data)

          # Email only in emails
          emails_user = create(:user, email: "user2@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user2" },
            { "name" => "emails", "value" => "user2@github.com" },
          ])
          create(:external_identity, provider: provider, user: emails_user, saml_user_data: saml_user_data)

          # Email only in claims/name
          claims_user = create(:user, email: "user3@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user3" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "value" => "user3@github.com" },
          ])
          create(:external_identity, provider: provider, user: claims_user, saml_user_data: saml_user_data)

          # Email only in claims/emailaddress
          claims_email_user = create(:user, email: "user4@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user4" },
            { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress", "value" => "user4@github.com" },
          ])
          create(:external_identity, provider: provider, user: claims_email_user, saml_user_data: saml_user_data)

          business.add_user_accounts([nameid_user.id, emails_user.id, claims_user.id, claims_email_user.id])

          expected_hash = {
            "user1@github.com" => nameid_user.business_user_accounts.find_by(business_id: business.id),
            "user2@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
            "user3@github.com" => claims_user.business_user_accounts.find_by(business_id: business.id),
            "user4@github.com" => claims_email_user.business_user_accounts.find_by(business_id: business.id),
          }

          emails = %w[user1@github.com user2@github.com user3@github.com user4@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end

        test "falls back to SAML username if no emails found and it looks like an email" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          provider = create :organization_saml_provider, organization: org

          user = create(:user, email: "user1@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "username", "value" => "user1@github.com" },
          ])
          create(:external_identity, provider: provider, user: user, saml_user_data: saml_user_data)
          business.add_user_accounts([user.id])

          expected_hash = {
            "user1@github.com" => user.business_user_accounts.find_by(business_id: business.id),
          }

          accounts_hash = business.dotcom_users_from_extid_emails(["user1@github.com"])
          assert_same_hash expected_hash, accounts_hash
        end

        test "prioritises SAML data over SCIM data" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          scim_provider = create :organization_saml_provider, organization: org
          saml_provider = create :organization_saml_provider, organization: org

          user = create(:user, email: "user5@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user5" },
            { "name" => "emails", "value" => "user.five@github.com" },
          ])
          create(:external_identity, provider: saml_provider, user: user, saml_user_data: saml_user_data)

          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User5-IdP-Id" },
            { "name" => "userName", "value" => "user5@github.com" },
          ])
          create(:external_identity, provider: scim_provider, user: user, scim_user_data: scim_user_data)

          business.add_user_accounts([user.id])
          Platform::Provisioning::ScimUserData.any_instance.expects(:emails).never
          business.dotcom_users_from_extid_emails(["user.five@github.com"])
        end

        test "is able to match by SCIM userName if SAML and SCIM emails do not match" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          scim_provider = create :organization_saml_provider, organization: org
          saml_provider = create :organization_saml_provider, organization: org

          user = create(:user, email: "user5@example.com")
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "user5" },
            { "name" => "emails", "value" => "user.five@github.com" },
          ])
          create(:external_identity, provider: saml_provider, user: user, saml_user_data: saml_user_data)

          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User5-IdP-Id" },
            { "name" => "userName", "value" => "User5@github.com" },
          ])
          create(:external_identity, provider: scim_provider, user: user, scim_user_data: scim_user_data)

          business.add_user_accounts([user.id])

          expected_hash = {
            "user5@github.com" => user.business_user_accounts.find_by(business_id: business.id),
          }
          accounts_hash = business.dotcom_users_from_extid_emails(["user5@github.com"])

          assert_same_hash expected_hash, accounts_hash
        end
      end

      context "Business with SCIM org" do
        test "finds all the BusinessUserAccounts associated with users that have the given email addresses" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          provider = create :organization_saml_provider, organization: org

          # Email only in emails
          emails_user = create(:user, email: "user5@example.com")
          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User5-IdP-Id" },
            { "name" => "emails", "value" => "user5@github.com" },
          ])
          create(:external_identity, provider: provider, user: emails_user, scim_user_data: scim_user_data)

          # Email only in username
          username_user = create(:user, email: "user6@example.com")
          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "User6-IdP-Id" },
            { "name" => "userName", "value" => "user6@github.com" },
          ])
          create(:external_identity, provider: provider, user: username_user, scim_user_data: scim_user_data)

          business.add_user_accounts([emails_user.id, username_user.id])

          expected_hash = {
            "user5@github.com" => emails_user.business_user_accounts.find_by(business_id: business.id),
            "user6@github.com" => username_user.business_user_accounts.find_by(business_id: business.id),
          }
          emails = %w[user5@github.com user6@github.com]
          accounts_hash = business.dotcom_users_from_extid_emails(emails)
          assert_same_hash expected_hash, accounts_hash
        end
      end

      test "returns an empty hash when no BusinessUserAccounts are found" do
        org = create :organization, billing_type: "invoice", plan: "business_plus"
        business = create :business, organizations: [org]
        provider = create :organization_saml_provider, organization: org

        user = create(:user, email: "user1@example.com")
        saml_user_data = Platform::Provisioning::SamlUserData.new([
          { "name" => "NameID", "value" => "user1@github.com" },
        ])
        create(:external_identity, provider: provider, user: user, saml_user_data: saml_user_data)

        business.add_user_accounts([user.id])

        expected_hash = {}

        emails = %w[user5@github.com user6@github.com]
        accounts_hash = business.dotcom_users_from_extid_emails(emails)
        assert_same_hash expected_hash, accounts_hash
      end
    end

    context "#all_saml_providers" do
      context "Business level SAML providers" do
        test "finds only the business level SAML provider" do
          org = create :organization, billing_type: "invoice", plan: "business_plus"
          business = create :business, organizations: [org]
          create :business_saml_provider
          create :organization_saml_provider, organization: org

          assert_equal 1, business.all_saml_providers.count
        end

        context "Organization level SAML providers" do
          test "finds all unique org level SAML providers" do
            org1 = create :organization, billing_type: "invoice", plan: "business_plus"
            org2 = create :organization, billing_type: "invoice", plan: "business_plus"
            business = create :business, organizations: [org1, org2]
            create :organization_saml_provider, organization: org1
            create :organization_saml_provider, organization: org2

            assert_equal 2, business.all_saml_providers.count
          end

          test "finds all shared org level SAML providers only once" do
            org1 = create :organization, billing_type: "invoice", plan: "business_plus"
            org2 = create :organization, billing_type: "invoice", plan: "business_plus"
            business = create :business, organizations: [org1, org2]
            create :organization_saml_provider, organization: org1, sso_url: "https://example.com/saml/sso", issuer: "https://example.com"
            create :organization_saml_provider, organization: org2, sso_url: "https://example.com/saml/sso", issuer: "https://example.com"

            assert_equal 1, business.all_saml_providers.count
          end
        end
      end
    end

    context "#enterprise_users_from_emails" do
      test "finds all the BusinessUserAccounts for server-only members with the given email addresses" do
        email_address = @enterprise_installation_user_account.emails.first.email
        accounts_hash = @business.enterprise_users_from_emails([email_address])
        expected_hash = { email_address => @business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end

      test "emails used as keys are always downcased" do
        email = "OCTOCAT@GITHUB.COM"
        business_user_account = create :business_user_account,
          business: @business, user: nil
        enterprise_installation_user_account = create :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        create :enterprise_installation_user_account_email,
          email: email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          primary: true

        accounts_hash = @business.enterprise_users_from_emails([email])
        expected_hash = { email.downcase => business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end

      test "emails and user account ids are sliced" do
        existing_email = @enterprise_installation_user_account.emails.first.email

        email = "octocatdos@github.github"
        business_user_account = create :business_user_account,
          business: @business, user: nil
        enterprise_installation_user_account = create :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account
        create :enterprise_installation_user_account_email,
          email: email,
          enterprise_installation_user_account: enterprise_installation_user_account,
          primary: true

        email_not_used = "octocattres@github.github"
        business_user_account_not_used = create :business_user_account,
          business: @business, user: nil
        enterprise_installation_user_account_not_used = create :enterprise_installation_user_account,
          enterprise_installation: @enterprise_installation,
          business_user_account: business_user_account_not_used
        create :enterprise_installation_user_account_email,
          email: email_not_used,
          enterprise_installation_user_account: enterprise_installation_user_account_not_used,
          primary: true

        accounts_hash = @business.enterprise_users_from_emails([email, existing_email], 1)
        expected_hash = { email.downcase => business_user_account, existing_email => @business_user_account }
        assert_same_hash expected_hash, accounts_hash
      end
    end

    context "#searchable?" do
      test "returns true when not destroyed" do
        assert_predicate @business, :searchable?
      end

      test "returns false when soft-deleted" do
        @deletable_business.soft_delete!
        refute_predicate @deletable_business, :searchable?
      end

      test "returns false when destroyed" do
        @business.destroy
        refute_predicate @business, :searchable?
      end
    end

    context "#synchronize_search_index" do
      test "indexes a business on create" do
        Timecop.freeze do
          timestamp = Timestamp.from_time(Time.now)
          owner = create :user
          business = Business.create({
            name: "Acme, Inc",
            billing_email: Faker::Internet.email,
            owners: [owner],
            seats: 100,
          })
          guid = AddToSearchIndexJob.guid("enterprise", business.id)

          assert_enqueued_with job: AddToSearchIndexJob, args: ["enterprise", business.id, { "submitted_at" => timestamp, "guid" => guid }]
        end
      end

      test "indexes a business on update" do
        Timecop.freeze(Time.now) do
          timestamp = Timestamp.from_time(Time.now)
          guid = AddToSearchIndexJob.guid("enterprise", @business.id)

          assert_enqueued_with job: AddToSearchIndexJob, args: ["enterprise", @business.id, { "submitted_at" => timestamp, "guid" => guid }] do
            @business.update name: "EEEEEEEEE, Ltd."
          end
        end
      end

      test "removes a business from the search index on soft-delete" do
        assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["enterprise", @deletable_business.id] do
          @deletable_business.soft_delete!
        end
      end

      test "indexes a business on restore" do
        @deletable_business.soft_delete!

        Timecop.freeze(Time.now) do
          timestamp = Timestamp.from_time(Time.now)
          guid = AddToSearchIndexJob.guid("enterprise", @deletable_business.id)

          assert_enqueued_with job: AddToSearchIndexJob, args: ["enterprise", @deletable_business.id, { "submitted_at" => timestamp, "guid" => guid }] do
            @deletable_business.restore!
          end
        end
      end

      test "removes a business from the search index on destroy" do
        # We need to perform the `Licensing::SnapshotLicensesJob` to avoid `assert_enqueued_with` raising
        # deserialization errors (see https://github.com/rails/rails/issues/39606 for details)
        perform_enqueued_jobs only: Licensing::SnapshotLicensesJob do
          assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["enterprise", @business.id] do
            @business.destroy!
          end
        end
      end
    end

    context "#add_collaborator_user_accounts?" do
      if GitHub.single_business_environment?
        test "always returns false in single business env" do
          refute_predicate @business, :add_collaborator_user_accounts?
        end
      else
        test "returns true for non-metered Business" do
          refute_predicate @business, :metered_ghe?
          assert_predicate @business, :add_collaborator_user_accounts?
        end

        test "returns true for metered Business" do
          @business.customer.update! metered_ghe: true
          assert_predicate @business, :metered_ghe?
          assert_predicate @business, :add_collaborator_user_accounts?
        end
      end
    end

    context "#include_user_attributes_on_user_account?" do
      if GitHub.single_business_environment?
        test "returns false in enterprise mode" do
          refute @business.include_attributes_on_user_account?
        end
      else
        test "returns true" do
          assert @business.include_attributes_on_user_account?
        end
      end
    end
  end

  context "#supports_unaffiliated_user_accounts?" do
    if GitHub.single_business_environment?
      test "returns false in enterprise mode" do
        refute @business.supports_unaffiliated_user_accounts?
      end

      test "returns true when server scim is enabled" do
        setup_saml_auth_mode(with_scim: true)
        business = create(:global_business)
        assert business.supports_unaffiliated_user_accounts?
      end
    else
      test "returns true for EMU accounts" do
        emu = create :emu
        assert emu.enterprise_managed_business.supports_unaffiliated_user_accounts?
      end

      test "returns true for basic accounts" do
        @business.update(seats_plan_type: :basic)
        assert @business.supports_unaffiliated_user_accounts?
      end

      test "returns false if unaffiliated_user_accounts flag is disabled" do
        disable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        refute @business.supports_unaffiliated_user_accounts?
      end

      test "returns true if unaffiliated_user_accounts flag is enabled" do
        enable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:enterprise_teams_migrate_from_cfb)
        assert @business.supports_unaffiliated_user_accounts?
      end

      test "returns true if enterprise_teams_migrate_from_cfb flag is enabled" do
        disable_feature_flag(:unaffiliated_user_accounts)
        enable_feature_flag(:enterprise_teams_migrate_from_cfb)
        assert @business.supports_unaffiliated_user_accounts?
      end
    end
  end

  context "#copilot_licensing_enabled" do
    test "default to false for non EMU on full plan" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      refute @business.copilot_licensing_enabled?
    end unless TestEnv.test_with_all_emus?

    unless GitHub.single_business_environment?
      test "defaults to false on EMU because default plan is full (when feature flag disabled)" do
        emu_owner = create :emu, :owner
        emu_enterprise = emu_owner.enterprise_managed_business
        refute emu_enterprise.copilot_licensing_enabled?
      end

      test "EMU on basic plan has access to copilot licensing at enterprise level" do
        emu_owner = create :emu, :owner
        emu_enterprise = emu_owner.enterprise_managed_business
        emu_enterprise.update(seats_plan_type: :basic)

        assert emu_enterprise.copilot_licensing_enabled?
      end

      test "when feature flag is enabled for an EMU, copilot licensing at enterprise level is not available on full plan" do
        emu_owner = create :emu, :owner
        emu_enterprise = emu_owner.enterprise_managed_business
        emu_enterprise.update(seats_plan_type: :full)

        refute emu_enterprise.copilot_licensing_enabled?
      end

      test "non-EMU on a basic plan has access to copilot licensing at enterprise level" do
        business = create :business, seats_plan_type: :basic
        assert business.copilot_licensing_enabled?
      end

      test "when feature flag is enabled for a non-EMU and unaffiliated user accounts enabled, copilot licensing at enterprise level is not available on full plan" do
        business = create :business, seats_plan_type: :full
        enable_feature_flag(:unaffiliated_user_accounts, business)

        refute business.copilot_licensing_enabled?
      end

      test "returns true for a metered business, when the copilot_metered_enterprise feature flag is enabled" do
        business = create :business
        business.customer.update!(metered_ghe: true, billing_type: Customer::BILLING_TYPE_CARD)
        enable_feature_flag(:copilot_metered_enterprise, business)

        assert business.copilot_licensing_enabled?
      end

      test "returns false for a metered business on trial, even if the copilot_metered_enterprise feature flag is enabled" do
        business = create :business
        business.customer.update!(metered_ghe: true, billing_type: Customer::BILLING_TYPE_CARD)
        business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        enable_feature_flag(:copilot_metered_enterprise, business)

        refute business.copilot_licensing_enabled?
      end
    end
  end

  context "#enterprise_teams_enabled" do

    # We have extensive tests for individual feature enabling, so we stub here not to duplicate all the tests
    # that would compose the or logic here.

    test "returns false when none of the features are enabled" do
      business = create :business

      business.stubs(:copilot_licensing_enabled?).returns(false)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      refute business.enterprise_teams_enabled?
    end

    test "returns true when copilot enabled" do
      owner = create :emu
      business = owner.enterprise_managed_business
      business.update(seats_plan_type: :basic)

      business.stubs(:copilot_licensing_enabled?).returns(true)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      assert business.enterprise_teams_enabled?
    end

    test "returns true when enterprise sync to orgs enabled" do
      owner = create :emu
      business = owner.enterprise_managed_business

      business.stubs(:copilot_licensing_enabled?).returns(false)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      assert business.enterprise_teams_enabled?
    end
  end unless GitHub.single_business_environment?

  context "#connected_enterprise_installations" do
    test "returns only enterprise installations where integration_id is not blank" do
      installation = create :enterprise_installation, owner: @business, integration_id: "123"
      create :enterprise_installation, owner: @business

      assert_equal 3, @business.enterprise_installations.count
      assert_equal [installation], @business.connected_enterprise_installations
    end
  end

  context "#terms_of_service_type_description" do
    values_and_descriptions = Business::TERMS_OF_SERVICE_TYPES.each_with_index.map do |value, index|
      [value, Business::TERMS_OF_SERVICE_TYPE_DESCRIPTIONS[index]]
    end

    values_and_descriptions.each do |value, description|
      test "returns '#{description}' when terms_of_service_type is '#{value}'" do
        @business.update terms_of_service_type: value
        assert_equal description, @business.terms_of_service_type_description
      end
    end
  end

  context "#terms_of_service_notes_html" do
    test "returns HTML" do
      @business.update terms_of_service_notes: "Notes that are very important"
      assert_equal \
        "<div>Notes that are very important</div>",
        @business.terms_of_service_notes_html
    end
  end

  context "::external_auth_system_owner_instructions" do
    test "raises ArgumentError when operation is invalid" do
      assert_raises ArgumentError do
        @business.external_auth_system_owner_instructions(operation: :something)
      end
    end

    test "returns the correct instructions for adding an owner when managed via LDAP" do
      GitHub.auth.stubs(:ldap?).returns(true)
      GitHub.auth.stubs(:name).returns("LDAP")
      GitHub.stubs(:ldap_admin_group).returns("acmeadmins")

      assert_equal \
        "Owners for the enterprise are managed via LDAP. Add owners by adding them to the LDAP admin group 'acmeadmins'.",
        @business.external_auth_system_owner_instructions(operation: :add)
    end

    test "returns the correct instructions for removing an owner when managed via LDAP" do
      GitHub.auth.stubs(:ldap?).returns(true)
      GitHub.auth.stubs(:name).returns("LDAP")
      GitHub.stubs(:ldap_admin_group).returns("acmeadmins")

      assert_equal \
        "Owners for the enterprise are managed via LDAP. Remove owners by removing them from the LDAP admin group 'acmeadmins'.",
        @business.external_auth_system_owner_instructions(operation: :remove)
    end

    test "returns the correct instructions for adding an owner when managed via SAML", enterprise_only: true do
      setup_saml_auth_mode
      GitHub.auth.stubs(:name).returns("Okta")

      assert_equal \
        "Owners for the enterprise are managed via Okta. Add owners by setting their SAML 'administrator' attribute to 'true'.",
        @business.external_auth_system_owner_instructions(operation: :add)
    end

    test "returns the correct instructions for removing an owner when managed via SAML", enterprise_only: true do
      setup_saml_auth_mode
      GitHub.auth.stubs(:name).returns("Okta")

      assert_equal \
        "Owners for the enterprise are managed via Okta. Remove owners by removing their SAML 'administrator' attribute.",
        @business.external_auth_system_owner_instructions(operation: :remove)
    end

    test "returns the correct instructions for adding an owner when managed via SCIM", enterprise_only: true do
      setup_saml_auth_mode(with_scim: true)

      assert_equal \
        "Owners for the enterprise are managed via SCIM. Add owners by assigning 'Enterprise Owner' application role to a user through SCIM provisioning via your IdP.",
        @business.external_auth_system_owner_instructions(operation: :add)
    end

    test "returns the correct instructions for removing an owner when managed via SCIM", enterprise_only: true do
      setup_saml_auth_mode(with_scim: true)

      assert_equal \
        "Owners for the enterprise are managed via SCIM. Remove owners by removing 'Enterprise Owner' application role from a user through SCIM provisioning via your IdP.",
        @business.external_auth_system_owner_instructions(operation: :remove)
    end
  end

  context "#has_s4_stats?" do
    test "returns false when an error occurs" do
      S4::V1::Client.any_instance
        .stubs(:count)
        .raises(S4::V1::Client::ResponseError.new(Twirp::Error.internal("whoops")))
      refute @business.has_s4_stats?
    end
  end

  context "#s4_usage_metrics" do
    test "returns empty metrics hash when an error occurs" do
      S4::V1::Client.any_instance
        .stubs(:filtered_metrics)
        .raises(S4::V1::Client::ResponseError.new(Twirp::Error.internal("whoops")))
      assert_equal(GitHub::Connect::S4::ERROR_METRICS_RESPONSE, @business.s4_usage_metrics)
    end
  end

  context "#send_welcome_net_new_enterprise_account_email" do
    unless GitHub.single_business_environment?
      context "ghec_receive_net_new_enterprise_account_email feature enabled" do
        test "sends welcome email if the business is not EMU enabled" do
          enable_feature_flag(:ghec_receive_net_new_enterprise_account_email)

          assert_enqueued_with(job: ApplicationDeliveryJob, at: 1.day.from_now) do
            @business.send_welcome_net_new_enterprise_account_email
          end

          job = enqueued_jobs.reverse.detect { |job| job["job_class"] == "ApplicationDeliveryJob" }

          assert_equal job["arguments"].first, "BusinessCampaignMailer"
          assert_equal job["arguments"].second, "welcome_net_new_enterprise_account"
        end

        test "sends welcome email if the business is EMU enabled" do
          enable_feature_flag(:ghec_receive_net_new_enterprise_account_email)

          business = create(:business, :enterprise_managed_business, :without_enterprise_managed_user_owner)
          owner = create(:user, login: "admin-user-2")
          business.add_owner(owner, actor: owner)

          assert_enqueued_with(job: ApplicationDeliveryJob, at: 1.day.from_now) do
            business.send_welcome_net_new_enterprise_account_email
          end

          job = enqueued_jobs.reverse.detect { |job| job["job_class"] == "ApplicationDeliveryJob" }

          assert_equal job["arguments"].first, "BusinessCampaignMailer"
          assert_equal job["arguments"].second, "welcome_net_new_enterprise_account"
        end

        context "GHES customer" do
          test "sends the GHES welcome email" do
            enable_feature_flag(:ghec_receive_net_new_enterprise_account_email)

            @business.enterprise_web_business_id = 3

            assert_enqueued_with(job: ApplicationDeliveryJob, at: 1.day.from_now) do
              @business.send_welcome_net_new_enterprise_account_email
            end

            job = enqueued_jobs.reverse.detect { |job| job["job_class"] == "ApplicationDeliveryJob" }

            assert_equal job["arguments"].first, "BusinessCampaignMailer"
            assert_equal job["arguments"].second, "welcome_net_new_enterprise_account_ghes"
          end
        end
      end
    end

    if GitHub.single_business_environment?
      context "ghec_receive_net_new_enterprise_account_email feature enabled" do
        test "does not sent email" do
          enable_feature_flag(:ghec_receive_net_new_enterprise_account_email)

          GlobalInstrumenter.expects(:instrument).with("customer_success_campaign.email", any_parameters).never

          assert_no_enqueued_jobs(only: ApplicationDeliveryJob) do
            @business.send_welcome_net_new_enterprise_account_email
          end
        end
      end
    end
  end

  context "#resource_creation_enabled" do
    unless GitHub.single_business_environment?
      test "should return false if the business's billing type is not card" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business)
        business.customer.update! billing_type: Customer::BILLING_TYPE_INVOICE
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return false if the business's country code is not US or CA" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business, country_code: "JP")

        refute business.resource_creation_enabled?
      end

      test "should return false if the business is EMU" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business, business_type: :enterprise_managed, shortcode: "abc")
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return false if the business has zero seat" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business, seats: 0)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return false if the business is part of the startup program" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business)
        startups_program = create(:business_startups_program, business: business, status: :year_1)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return false if the business redeemed startup program coupon" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        coupon = create(:coupon, group: "startup-program", plan: "business_plus", code: "GFSYR1")
        business = create(:business, :with_credit_card)
        owner = business.owners.first
        business.redeem_coupon(coupon.code, actor: owner)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return false if the business redeemed startup program coupon with prefix" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        coupon = create(:coupon, group: "startup-program", plan: "business_plus", code: "gfs-abcd1234")
        business = create(:business, :with_credit_card)
        owner = business.owners.first
        business.redeem_coupon(coupon.code, actor: owner)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        refute business.resource_creation_enabled?
      end

      test "should return true if none of the above conditions are met" do
        enable_feature_flag(:onboarding_resources_link_in_email)
        business = create(:business)
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        profile = create(:account_screening_profile, :with_business, owner: business)

        assert business.resource_creation_enabled?
      end
    end
  end

  context "#unique_slug" do
    test "returns an empty string if an invalid base string is passed in" do
      assert_equal "", Business.unique_slug(nil)
    end

    test "returns the base string as a suggested string if it is available to be used as a Business slug" do
      base_string = "my-account"
      refute Business.including_deleted.find_by(slug: base_string).present?

      assert_equal "my-account", Business.unique_slug(base_string)
    end

    test "returns the base string + a numerical suffix if the base string is already being used as a Business slug" do
      base_string = "my-account"
      business = create(:business, slug: base_string, owners: [@owner])  # Create existing EA with the base slug
      assert Business.including_deleted.find_by(slug: base_string).present?

      assert_equal "my-account-2", Business.unique_slug(base_string)  # The naming starts at '-2'
    end

    test "returns an empty string if the number of attempts to append a numerical suffix has exceeded 12" do
      base_string = "my-account"
      business = create(:business, slug: base_string, owners: [@owner])
      2.upto(11) do |dup|
        business = create :business, name: base_string
        assert business.slug.ends_with?("#{base_string}-#{dup}")
      end  # Create 12 businesses with the base slug

      assert_equal "", Business.unique_slug(base_string)  # Attempts to append a numerical suffix should exceed 12
    end
  end unless GitHub.enterprise?

  context "#has_many" do
    test "enterprise teams are destroyed when business is destroyed" do
      business = create :business
      business_id = business.id
      enterprise_team1 = create :enterprise_team, business: business
      enterprise_team2 = create :enterprise_team, business: business
      assert_same_elements [enterprise_team1, enterprise_team2], business.enterprise_teams
      business.destroy
      assert_empty EnterpriseTeam.where(business_id: business_id)
    end unless GitHub.single_business_environment?

    test "enterprise can have multiple integration transfer" do
      business = GitHub.global_business || create(:business)
      integration1 = create :integration
      integration2 = create :integration
      xfer1 = IntegrationTransfer.start(integration: integration1, target: business, requester: integration1.owner)
      xfer2 = IntegrationTransfer.start(integration: integration2, target: business, requester: integration2.owner)
      assert_same_elements [xfer1, xfer2], business.inbound_integration_transfers
    end
  end

  context "#transfer_organization" do
    test "does not trigger pages soft deletion" do
      enable_feature_flag(:pages_soft_deletion)

      business = create(:business)
      organization = create(:organization, business: business)
      new_business = create(:business)

      assert_enqueued_jobs(0, only: DestroyPrivatePageJob) do
        business.transfer_organization(organization, new_business)
      end
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "keeps the org maximum token lifetime configuration on the organization" do
      business = create(:business, owners: [@owner])
      organization = create(:organization, business: business, admin: @owner)
      new_business = create(:business, owners: [@owner])
      organization.set_personal_access_token_classic_expiration_limit(actor: @owner, expiration: 40)
      organization.set_fine_grained_personal_access_token_expiration_limit(actor: @owner, expiration: 50)
      business.set_personal_access_token_classic_expiration_limit(actor: @owner, expiration: 20)
      business.set_fine_grained_personal_access_token_expiration_limit(actor: @owner, expiration: 30)

      perform_enqueued_jobs only: [BusinessUserAccountCreateForOrganizationJob] do
        business.transfer_organization(organization, new_business, actor: @owner)
      end

      assert_equal new_business, organization.reload.business
      assert_equal 40, organization.personal_access_token_classic_expiration_limit
      assert_equal 50, organization.fine_grained_personal_access_token_expiration_limit
    end

    test "uses the enterprise maximum token lifetime configuration on the organization if organization does not have a policy set" do
      business = create(:business, owners: [@owner])
      organization = create(:organization, business: business, admin: @owner)
      new_business = create(:business, owners: [@owner])
      business.set_personal_access_token_classic_expiration_limit(actor: @owner, expiration: 20)
      business.set_fine_grained_personal_access_token_expiration_limit(actor: @owner, expiration: 30)

      perform_enqueued_jobs only: [BusinessUserAccountCreateForOrganizationJob] do
        business.transfer_organization(organization, new_business, actor: @owner)
      end

      assert_equal new_business, organization.reload.business
      assert_equal 20, organization.personal_access_token_classic_expiration_limit
      assert_equal 30, organization.fine_grained_personal_access_token_expiration_limit
    end
  end unless GitHub.single_business_environment?

  context "#add_organization" do
    test "restores soft deleted pages" do
      enable_feature_flag(:pages_soft_deletion)

      business = create(:business)
      organization = create(:organization)

      assert_enqueued_jobs(1, only: RestoreSoftDeletedPagesJob) do
        business.add_organization(organization)
      end
    end unless GitHub.single_or_multi_tenant_enterprise?
  end

  context "#remove_organization" do
    test "soft deletes private pages when the organization plan does not allow them" do
      enable_feature_flag(:pages_soft_deletion)

      business = create(:business)
      organization = create(:organization, business: business)
      private_page = create(:private_page, owner: organization)
      public_page = create(:page, owner: organization)

      perform_enqueued_jobs(only: [DestroyPrivatePageJob]) do
        business.remove_organization(organization)
      end

      assert private_page.reload.soft_deleted?
      refute public_page.reload.soft_deleted?
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "soft deletes pages of private repos when the organization plan does not allow them" do
      enable_feature_flag(:pages_soft_deletion)

      business = create(:business)
      organization = create(:organization, plan: "free", business: business)
      private_repo = create(:private_repository, owner: organization)
      private_repo_page = create(:page, repository: private_repo)
      private_repo_page.update!(public: true)
      public_page = create(:page, owner: organization)

      perform_enqueued_jobs(only: [DestroyPrivatePageJob]) do
        business.remove_organization(organization)
      end

      assert private_repo_page.reload.soft_deleted?
      refute public_page.reload.soft_deleted?
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "sets the organization seats to its previous value when removed from a business on trial" do
      original_org_seats = 5
      @business.trial_expires_at = 30.days.from_now
      org = create(:organization, plan: GitHub::Plan.business, seats: original_org_seats)
      @business.add_organization(org)
      assert_equal org.reload.seats, @business.seats

      @business.remove_organization(org, actor: create(:staff_admin_user))
      assert_equal org.seats, original_org_seats
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "sets the organization's seats to 0 when business is not on trial" do
      owner = create(:user)
      org = create(:organization, plan: "free")
      only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
      business = perform_enqueued_jobs only: only do
        create :business, owners: [owner], organizations: [org], seats: 20
      end
      refute business.trial?
      refute business.trial_expired?
      refute business.trial_cancelled?
      # The SyncBusinessOrganizationBillingSettingsJob syncs the org's seats with the business's seats
      assert_equal org.reload.seats, 20
      business.remove_organization(org)
      assert_equal org.seats, 0
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "uninstalls enterprise owned apps when an org is removed from the enterprise" do
      owner = create :user
      business = create :business, owners: [owner]
      org = create :organization, business: business

      integration = create :enterprise_owned_integration, owner: business
      enterprise_integration_installation = make_integration_installation(target: org, integration: integration)
      # a non-enterprise owned app should stay
      integration_installation = make_integration_installation(target: org)

      assert_equal org.integration_installations.count, 2
      assert_includes org.integration_installations, enterprise_integration_installation
      assert_includes org.integration_installations, integration_installation
      business.remove_organization(org)
      assert_equal org.integration_installations.count, 1
      refute_includes org.integration_installations, enterprise_integration_installation
      assert_includes org.integration_installations, integration_installation
    end unless GitHub.single_or_multi_tenant_enterprise?

    test "sends confirmation email for a normal delete", skip_if_feature_enabled: :enterprise_teams_migrate_from_cfb do
      GitHub.stubs(:proxima_billing_enabled?).returns(true)
      organization = create(:organization, business: @business)

      assert_enqueued_jobs(1, only: [ApplicationDeliveryJob]) do
        @business.remove_organization(organization)
      end

      queued_email_jobs = enqueued_jobs.select do |job|
        job["job_class"] == "ApplicationDeliveryJob" && \
        job["arguments"].first == "BusinessMailer" && \
        job["arguments"].second == "organization_removed_from_business"
      end
      assert_equal queued_email_jobs.count, 1
    end

    test "does not send confirmation email for transfers" do
      organization = create(:organization, business: @business)

      assert_enqueued_jobs(0, only: [ApplicationDeliveryJob]) do
        @business.remove_organization(organization, is_transfer: true)
      end
    end

    test "does not send confirmation email when gh_role=staff_delete" do
      organization = create(:organization, business: @business, gh_role: "staff_delete")

      assert_enqueued_jobs(0, only: [ApplicationDeliveryJob]) do
        @business.remove_organization(organization)
      end
    end
  end

  context "#add_users_to_organizations" do
    test "adds all users to all organizations and enqueues job" do
      assert_enqueued_jobs 1, only: OrganizationOrchestrationJob do
        @business.add_users_to_organizations([@member1.id, @member2.id], [@org1.id, @org2.id], actor: @owner)
      end

      Configuration::Entry.expects(:targeting_user_ids).never

      assert @org1.member?(@member1)
      assert @org2.member?(@member1)
      assert @org1.member?(@member2)
      assert @org2.member?(@member2)
    end

    test "adding users to orgs skips checking for 2fa on users/orgs if enabled at business level", skip_enterprise: true do
      owner = create :two_factor_credential_user
      business = create :business, owners: [owner]
      org1 = create :organization, business: business, admin: owner
      org2 = create :organization, business: business, admin: owner
      business.enable_two_factor_required(actor: owner, force: true)
      assert_predicate business, :two_factor_requirement_enabled?

      user_2fa_enabled = create :two_factor_credential_user
      org1.add_member(user_2fa_enabled)

      Configuration::Entry.expects(:targeting_user_ids).never

      assert_enqueued_jobs 1, only: OrganizationOrchestrationJob do
        business.add_users_to_organizations([user_2fa_enabled.id], [org1.id, org2.id], actor: owner)
      end
    end

    test "does nothing for users that are already members of all orgs" do
      @org2.add_member(@member1)
      assert_enqueued_jobs 0, only: OrganizationOrchestrationJob do
        @business.add_users_to_organizations([@member1.id], [@org1.id, @org2.id], actor: @owner)
      end
      assert_equal "skipped", OrganizationOrchestration.last&.state

      assert @org1.member?(@member1)
      assert @org2.member?(@member1)
    end

    test "adds OrganizationMembershipEntry for new members if caller_type is enterprise_team" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team_1 = create(:team, organization: @org1)
      org_team_2 = create(:team, organization: @org2)
      enterprise_team_1 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      enterprise_team_2 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      org_mapping_1 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_1, organization: @org1, team: org_team_1)
      org_mapping_2 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_2, organization: @org2, team: org_team_2)

      @business.add_users_to_organizations([@member1.id, @member2.id], [@org1.id, @org2.id], actor: @owner, caller_type: :enterprise_team, team_ids: [org_team_1.id, org_team_2.id])

      assert OrganizationMembershipEntry.where(organization: @org2, user: @member1, adder_type: :enterprise_team).exists?
      assert OrganizationMembershipEntry.where(organization: @org1, user: @member2, adder_type: :enterprise_team).exists?
    end

    test "does not add OrganizationMembershipEntry if caller_type is nil" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team_1 = create(:team, organization: @org1)
      org_team_2 = create(:team, organization: @org2)
      enterprise_team_1 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      enterprise_team_2 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      org_mapping_1 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_1, organization: @org1, team: org_team_1)
      org_mapping_2 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_2, organization: @org2, team: org_team_2)
      @business.add_users_to_organizations([@member1.id, @member2.id], [@org1.id, @org2.id], actor: @owner, team_ids: [org_team_1.id, org_team_2.id])
      refute OrganizationMembershipEntry.where(organization: @org2, user: @member1, adder_type: :enterprise_team).exists?
      refute OrganizationMembershipEntry.where(organization: @org1, user: @member2, adder_type: :enterprise_team).exists?
    end

    test "does not add OrganizationMembershipEntry if team_ids is nil" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team_1 = create(:team, organization: @org1)
      org_team_2 = create(:team, organization: @org2)
      enterprise_team_1 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      enterprise_team_2 = create :enterprise_team, business: @business, sync_to_organizations: "all"
      org_mapping_1 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_1, organization: @org1, team: org_team_1)
      org_mapping_2 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team_2, organization: @org2, team: org_team_2)
      @business.add_users_to_organizations([@member1.id, @member2.id], [@org1.id, @org2.id], actor: @owner, caller_type: :enterprise_team)
      refute OrganizationMembershipEntry.where(organization: @org2, user: @member1, adder_type: :enterprise_team).exists?
      refute OrganizationMembershipEntry.where(organization: @org1, user: @member2, adder_type: :enterprise_team).exists?
    end

    unless GitHub.single_business_environment?
      test "does nothing for users that are not enterprise members" do
        non_member = create(:user)
        @business.add_users_to_organizations([non_member.id], [@org1.id, @org2.id], actor: @owner)

        refute @org1.member?(non_member)
        refute @org2.member?(non_member)
      end

      test "does nothing for organizations that are not enterprise members" do
        org = create(:organization)
        @business.add_users_to_organizations([@member1.id], [org.id], actor: @owner)

        refute org.member?(@member1)
        refute org.member?(@member1)
      end
    end
  end
end
