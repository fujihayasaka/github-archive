# typed: true
# frozen_string_literal: true

require "test_helper"

class AccountScreeningProfileTest < GitHub::TestCase
  include TradeCompliance::TradeScreening::TradeScreeningTestHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers
  skip_enterprise

  include AuditLog::IntegrationTestHelpers
  include Billing::AddressLookupTestHelpers
  include GitHub::LoggerHelper

  TEST_SDN_STATUS_REMOVE_ALLOW_LIST = [
    :not_screened,
    :no_hit,
    :ingestion_error,
    :data_issue,
  ].freeze

  PROFILE_PII_FIELDS = %w[
    first_name
    last_name
    middle_name
    entity_name
    region
    city
    country_code
    postal_code
    address1
    address2
  ].freeze

  def new_user_profile(**attributes)
    AccountScreeningProfile.new(
      first_name: "John",
      last_name: "Doe",
      address1: "123 Example Street",
      city: "London",
      country_code: "GB",
      postal_code: "LO12 3DN",
      **attributes
    )
  end

  def new_entity_profile(**attributes)
    AccountScreeningProfile.new(
      entity_name: "Example Ltd",
      address1: "123 Example Street",
      city: "London",
      country_code: "GB",
      postal_code: "LO12 3DN",
      vat_code: "GB123456789",
      **attributes
    )
  end

  fixtures do
    @owner = create(:user, login: "owner")
    @staff = create(:staff_admin_user)
    @org = create(:organization)
    @business = create(:business)
    @business_with_screening_record = create(:business, :with_trade_screening_record)
    @org_with_screening_record = create(:organization, :with_trade_screening_record)
    @user_with_screening_record = create(:user, :with_trade_screening_record)
  end

  setup do
    response = TradeCompliance::TradeScreening::LiveResponse.new(external_uuid: "", eid: "", status: "no_hit", status_reason: "")
    TradeCompliance::TradeScreening::ApiService.stubs(:make_live_request).returns(response)
  end

  context "validation" do
    context "without owner" do
      test "require that it belongs to a Owner" do
        personal_profile = build(:account_screening_profile, owner: nil)
        personal_profile.save

        refute_predicate personal_profile, :valid?
        assert_includes personal_profile.errors[:owner_id], "can't be blank"
      end

      test "can validate using user validation context" do
        assert new_user_profile.valid?(:user)
      end

      test "can validate using entity validation context" do
        assert new_entity_profile.valid?(:entity)
      end

      test "user validation context requires first name" do
        personal_profile = new_user_profile(first_name: nil)

        refute personal_profile.valid?(:user)
        assert_includes personal_profile.errors[:first_name], "can't be blank"
      end

      test "user validation context requires last name" do
        personal_profile = new_user_profile(last_name: nil)

        refute personal_profile.valid?(:user)
        assert_includes personal_profile.errors[:last_name], "can't be blank"
      end

      test "entity validation context requires entity name" do
        personal_profile = new_entity_profile(entity_name: nil)

        refute personal_profile.valid?(:entity)
        assert_includes personal_profile.errors[:entity_name], "can't be blank"
      end

      test "entity validation context requires VAT code for high risk country" do
        personal_profile = new_entity_profile(vat_code: nil, country_code: "CN")

        refute personal_profile.valid?(:entity)
        assert_includes personal_profile.errors[:vat_code], "can't be blank"
      end
    end

    test "default screening status is not_screened" do
      personal_profile = create(:account_screening_profile)
      assert personal_profile.not_screened?
    end

    test "require that User is unique" do
      personal_profile = create(:account_screening_profile, owner: @owner)
      personal_profile_copy = personal_profile.dup
      personal_profile_copy.save

      refute_predicate personal_profile_copy, :valid?
      assert_includes personal_profile_copy.errors[:owner_id], "has already been taken"
    end

    test "require that first name is present" do
      personal_profile = build(:account_screening_profile, first_name: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:first_name], "can't be blank"
    end

    test "require that first name is 2 or more characters" do
      personal_profile = build(:account_screening_profile, first_name: "A")
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:first_name], "is too short"
    end

    test "require that last name is present" do
      personal_profile = build(:account_screening_profile, last_name: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:last_name], "can't be blank"
    end

    test "require that last name is 2 or more characters" do
      personal_profile = build(:account_screening_profile, last_name: "")
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:last_name], "is too short"
    end

    test "require that entity name is present for business profiles" do
      personal_profile = build(:account_screening_profile, owner: @business, first_name: nil, last_name: nil, entity_name: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:entity_name], "can't be blank"
    end

    test "allows first and last name and entity name to be set at the same time" do
      profile = build(:account_screening_profile, entity_name: "Acme Inc", first_name: "John", last_name: "Doe")
      profile.save

      assert_predicate profile, :valid?
    end

    test "does not require first name to be present if owner is a user and status is true_match" do
      profile = build(:account_screening_profile, owner: @owner, first_name: nil, msft_trade_screening_status: "true_match")
      profile.save!

      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
    end

    test "does not require first name to be present for pseudo records if owner is a user and status is no_hit" do
      profile = build(:account_screening_profile, owner: @owner, first_name: nil, msft_trade_screening_status: "no_hit")
      profile.save!

      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
    end

    test "does not require first name to be present for pseudo records with status no_hit on internal updates" do
      profile = build(:account_screening_profile, owner: @owner, first_name: nil, msft_trade_screening_status: "no_hit")
      profile.save!
      profile.true_match!

      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
    end

    test "does not require first name to be valid for internal updates" do
      profile = build(:account_screening_profile, owner: @owner, first_name: nil, msft_trade_screening_status: "hit_in_review")
      profile.save!(validate: false)
      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
      assert_predicate profile, :hit_in_review?

      profile.update(msft_trade_screening_status: "lic_r")
      assert_predicate profile.reload, :lic_r?
      refute_predicate profile.errors, :empty?
      refute_predicate profile, :valid?
    end

    test "requires first name to be present for pseudo records with status no_hit for non-internal updates" do
      profile = build(:account_screening_profile, owner: @owner, msft_trade_screening_status: "no_hit")
      profile.save!
      profile.update(first_name: "")

      refute_predicate profile, :valid?
      assert_includes profile.errors[:first_name], "can't be blank"
    end

    test "allows update of pseudo records with status no_hit for non-internal updates when all data is valid" do
      GitHub.flipper[:live_sdn_screening].enable
      profile = create(:account_screening_profile, :lic_r_enabled_and_restricted)

      profile.update(country_code: "DE", address1: "123 Main St", city: "New York", entity_name: "Test Inc.")

      assert_predicate profile.errors, :empty?
      assert_predicate profile, :valid?
    end

    test "does not require last name to be present for pseudo records if owner is a user and status is true_match" do
      profile = build(:account_screening_profile, owner: @owner, last_name: nil, msft_trade_screening_status: "true_match")
      profile.save!

      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
    end

    test "does not require last name to be present for pseudo records if owner is a user and status is no_hit" do
      profile = build(:account_screening_profile, owner: @owner, last_name: nil, msft_trade_screening_status: "no_hit")
      profile.save!

      assert_predicate profile, :persisted?
      refute_predicate profile, :valid?
    end

    test "require that entity name is present if owner is a business org and status is not lic_r or no_hit" do
      owner = create(:user, :verified)
      org = create(:organization, admin: owner)
      org.terms_of_service.update(type: "Corporate", actor: owner)

      profile = build(:account_screening_profile, owner: org, entity_name: nil, msft_trade_screening_status: "hit_in_review")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:entity_name], "can't be blank"
    end

    test "require that tax id is present if owner is a CToS org and country is high risk" do
      owner = create(:user, :verified)
      org = create(:organization, admin: owner)
      org.terms_of_service.update(type: "Corporate", actor: owner)

      profile = build(:account_screening_profile, :with_org, owner: org, vat_code: nil, country_code: "CN")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:vat_code], "can't be blank"
    end

    test "does not require tax id to be present if owner is a CToS org and country is not high risk" do
      owner = create(:user, :verified)
      org = create(:organization, admin: owner)
      org.terms_of_service.update(type: "Corporate", actor: owner)

      profile = build(:account_screening_profile, :with_org, owner: org, vat_code: nil, country_code: "US")
      profile.save

      assert_predicate profile, :persisted?
      assert_predicate profile, :valid?
    end

    test "require that tax id is present if owner is a business and country is high risk" do
      profile = build(:account_screening_profile, :with_business, vat_code: nil, country_code: "CN", msft_trade_screening_status: "hit_in_review")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:vat_code], "can't be blank"
    end

    test "does not require tax id to be present if owner is a business and country is not high risk" do
      profile = build(:account_screening_profile, :with_business, vat_code: nil, country_code: "US", msft_trade_screening_status: "hit_in_review")
      profile.save

      assert_predicate profile, :persisted?
      assert_predicate profile, :valid?
    end

    TradeControls::Countries::POSTAL_CODE_REQUIRED_GEOS.each do |country|
      test "require that postal_code is present if owner is an org signed unto GitHub Customer Terms and country is #{country}" do
        owner = create(:user, :verified)
        org = create(:organization, admin: owner)
        org.terms_of_service.update(type: "Corporate", actor: owner)

        profile = build(:account_screening_profile, :with_org, owner: org, postal_code: nil, country_code: country)
        profile.save

        refute_predicate profile, :valid?
        assert_includes profile.errors[:postal_code], "can't be blank"
      end

      test "require that postal_code is present if owner is a business and country is #{country}" do
        profile = build(:account_screening_profile, :with_business, postal_code: nil, country_code: country)
        profile.save

        refute_predicate profile, :valid?
        assert_includes profile.errors[:postal_code], "can't be blank"
      end

      test "require that postal_code is present if owner is a user and country is #{country}" do
        profile = build(:account_screening_profile, postal_code: nil, country_code: country)
        profile.save

        refute_predicate profile, :valid?
        assert_includes profile.errors[:postal_code], "can't be blank"
      end
    end

    test "does not require postal_code to be present if owner is an org signed unto GitHub Customer Terms and country is not UA, US or RU" do
      owner = create(:user, :verified)
      org = create(:organization, admin: owner)
      org.terms_of_service.update(type: "Corporate", actor: owner)

      profile = build(:account_screening_profile, :with_org, owner: org, postal_code: nil, country_code: "DE")
      profile.save

      assert_predicate profile, :persisted?
      assert_predicate profile, :valid?
    end

    test "does not require postal_code to be present if owner is a business and country is not UA, US or RU" do
      profile = build(:account_screening_profile, :with_business, postal_code: nil, country_code: "DE")
      profile.save

      assert_predicate profile, :persisted?
      assert_predicate profile, :valid?
    end

    test "does not require postal_code to be present if owner is a user and country is not UA, US or RU" do
      profile = build(:account_screening_profile, postal_code: nil, country_code: "DE")
      profile.save

      assert_predicate profile, :persisted?
      assert_predicate profile, :valid?
    end

    test "requires address1 to be present if owner is an org and status is lic_r" do
      profile = build(:account_screening_profile, :with_org, address1: "", msft_trade_screening_status: "lic_r")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:address1], "can't be blank"
    end

    test "requires address1 to be present if owner is an org and status is no_hit" do
      profile = build(:account_screening_profile, :with_org, address1: "", msft_trade_screening_status: "no_hit")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:address1], "can't be blank"
    end

    test "require that address1 is present if owner is an org and status is not lic_r or no_hit" do
      profile = build(:account_screening_profile, :with_org, address1: "", msft_trade_screening_status: "hit_in_review")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:address1], "can't be blank"
    end

    test "requires city to be present if owner is an org and status is lic_r" do
      profile = build(:account_screening_profile, :with_org, city: "", msft_trade_screening_status: "lic_r")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:city], "can't be blank"
    end

    test "requires city to be present if owner is an org and status is no_hit" do
      profile = build(:account_screening_profile, :with_org, city: "", msft_trade_screening_status: "no_hit")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:city], "can't be blank"
    end

    test "require that city is present if owner is an org and status is not lic_r or no_hit" do
      profile = build(:account_screening_profile, :with_org, city: "", msft_trade_screening_status: "hit_in_review")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:city], "can't be blank"
    end

    test "requires country_code to be present if owner is an org and status is lic_r" do
      profile = build(:account_screening_profile, :with_org, country_code: "", msft_trade_screening_status: "lic_r")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:country_code], "can't be blank"
    end

    test "requires country_code to be present if owner is an org and status is no_hit" do
      profile = build(:account_screening_profile, :with_org, country_code: "", msft_trade_screening_status: "no_hit")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:country_code], "can't be blank"
    end

    test "requires that country_code is present if owner is an org and status is not lic_r or no_hit" do
      profile = build(:account_screening_profile, :with_org, country_code: nil, msft_trade_screening_status: "hit_in_review")
      profile.save

      refute_predicate profile, :valid?
      assert_includes profile.errors[:country_code], "can't be blank"
    end

    test "require that address is present" do
      personal_profile = build(:account_screening_profile, address1: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:address1], "can't be blank"
    end

    test "require that city is present" do
      personal_profile = build(:account_screening_profile, city: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:city], "can't be blank"
    end

    test "require that country code is present" do
      personal_profile = build(:account_screening_profile, country_code: nil)
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:country_code], "can't be blank"
    end

    test "require that owner is a valid type" do
      personal_profile = build(:account_screening_profile, owner_type: "RandomType")
      personal_profile.save

      refute_predicate personal_profile, :valid?
      assert_includes personal_profile.errors[:owner], "must be an enterprise account or user"
    end

    test "create sets external_uuid" do
      personal_profile = build(:account_screening_profile)

      assert personal_profile.save
      assert personal_profile.external_uuid
    end

    test "external_uuid is static on update" do
      personal_profile = create(:account_screening_profile)
      uuid = personal_profile.external_uuid

      assert uuid

      personal_profile.first_name = "Mike"
      personal_profile.save

      assert_equal personal_profile.external_uuid, uuid
    end

    test "create sets status_reason if none set for data_issue status and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "status:data_issue"
      ]

      personal_profile = build(:account_screening_profile, msft_trade_screening_status: "data_issue")

      assert personal_profile.save
      refute_empty personal_profile.metadata
      assert_predicate personal_profile.screening_status_reason, :present?
      assert_equal 1, stats.increments("sdn.status_reason.missing", tags: expected_tags).count
    end

    test "update sets status_reason if none set for data_issue status and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "status:data_issue"
      ]

      personal_profile = build(:account_screening_profile)
      assert personal_profile.save

      personal_profile.data_issue!

      refute_empty personal_profile.metadata
      assert_predicate personal_profile.screening_status_reason, :present?
      assert_equal "Data Issue - Missing", personal_profile.screening_status_reason
      assert_equal 1, stats.increments("sdn.status_reason.missing", tags: expected_tags).count
    end

    test "update removes blank keys/values from metadata" do
      personal_profile = build(:account_screening_profile)
      assert personal_profile.save

      personal_profile.metadata = { "": "test", "key": "", "key2": "value" }
      assert personal_profile.save

      assert_equal 1, personal_profile.metadata.count
    end

    test "update removes previous status_reason from metadata when SDN status changes and reason isn't set" do
      personal_profile = build(:account_screening_profile, msft_trade_screening_status: "data_issue", metadata: { "status_reason": "Data Issue - Missing" })
      assert personal_profile.save

      personal_profile.lic_r!

      assert_nil personal_profile.screening_status_reason
    end

    test "create removes blank keys/values from metadata" do
      personal_profile = build(:account_screening_profile, msft_trade_screening_status: "lic_r", metadata: { "": "test", "key": "" })

      assert personal_profile.save
      assert_nil personal_profile.screening_status_reason
    end

    test "create doesn't set status_reason if already set for data_issue status and doesn't report to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "status:data_issue"
      ]

      personal_profile = build(:account_screening_profile, msft_trade_screening_status: "data_issue", metadata: { "status_reason": "test" })

      assert personal_profile.save
      refute_empty personal_profile.metadata
      assert_predicate personal_profile.screening_status_reason, :present?
      assert_equal "test", personal_profile.screening_status_reason
      assert_equal 0, stats.increments("sdn.status_reason.missing", tags: expected_tags).count
    end

    test "create doesn't set status_reason for non-data_issue status and doesn't report to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "status:data_issue"
      ]

      personal_profile = build(:account_screening_profile, msft_trade_screening_status: "lic_r", metadata: { "test_key": "test" })

      assert personal_profile.save
      refute_empty personal_profile.metadata
      refute_predicate personal_profile.screening_status_reason, :present?
      assert_equal 0, stats.increments("sdn.status_reason.missing", tags: expected_tags).count
    end
  end

  context "#sync_to_contact" do
    test "syncs screening profile to contact both on create and on update with existing customer record" do
      owner = create(:business, :with_self_serve_payment)
      owner.disable_feature(:read_billing_information_from_contacts)
      customer = owner.customer
      shipping_contact = create(:shipping_contact, customer: customer)

      assert_equal 1, owner.customer.contacts.size
      screening_profile = create(:account_screening_profile, :with_business, owner: owner)
      assert_equal 2, owner.customer.contacts.size

      billing_contact = owner.customer.contacts.find { |contact| contact.billing? }
      assert_nil billing_contact.first_name
      assert_nil billing_contact.last_name
      assert_equal screening_profile.entity_name, billing_contact.entity_name
      assert_equal screening_profile.address1, billing_contact.address1
      assert_nil billing_contact.address2
      assert_equal screening_profile.city, billing_contact.city
      assert_equal screening_profile.region, billing_contact.region
      assert_equal screening_profile.country_code, billing_contact.country_code
      assert_equal screening_profile.postal_code, billing_contact.postal_code
      assert_equal screening_profile.billing_trade_screening_status, billing_contact.trade_screening_status
      assert screening_profile.reload.metadata["migrated_to_contacts"]

      # should work for only PII data change
      screening_profile.update(entity_name: "Sparrows Inc.")
      assert_equal 2, owner.reload.customer.contacts.size
      assert_equal "Sparrows Inc.", billing_contact.reload.entity_name

      # should work for only billing screening status change
      assert_predicate billing_contact, :not_screened?
      screening_profile.update(billing_trade_screening_status: "no_hit")
      assert_predicate billing_contact.reload, :no_hit?

      # should work for only address validated at change
      assert_nil billing_contact.address_validated_at
      screening_profile.update(billing_address_validated_at: Time.now.utc)
      refute_nil billing_contact.reload.address_validated_at
    end

    test "syncs screening profile to contact both on create and on update with new customer record" do
      business = create(:business, customer: nil)
      business.disable_feature(:read_billing_information_from_contacts)
      assert_nil business.customer

      # on create
      business_screening_profile = create(:account_screening_profile, :with_business, owner: business)
      refute_nil business.reload.customer
      assert_equal 1, business.customer.contacts.size
      assert business_screening_profile.reload.metadata["migrated_to_contacts"]

      user = create(:user)
      assert_nil user.customer
      user.enable_feature(:read_billing_information_from_contacts)
      user_screening_profile = create(:account_screening_profile, skip_contact_creation: true, owner: user)
      assert_nil user.reload.customer
      refute user_screening_profile.reload.metadata["migrated_to_contacts"]
      # on update
      user.disable_feature(:read_billing_information_from_contacts)
      user_screening_profile.update(first_name: "Kudos")
      refute_nil user.reload.customer
      assert_equal 1, user.customer.contacts.size
      assert user_screening_profile.reload.metadata["migrated_to_contacts"]
      assert_dogstats_increment(2, "sync_billing_info.new_customer_created")
    end

    test "syncs user screening profile that has first/last/entity name set to contact" do
      owner = create(:user, customer: nil)
      owner.disable_feature(:read_billing_information_from_contacts)
      assert_nil owner.customer

      # on create
      screening_profile = create(:account_screening_profile, owner: owner, entity_name: "foo")
      refute_nil owner.reload.customer
      assert_equal 1, owner.customer.contacts.size
      assert screening_profile.reload.metadata["migrated_to_contacts"]
      assert_predicate screening_profile.first_name, :present?
      assert_predicate screening_profile.last_name, :present?
      assert_equal "foo", screening_profile.entity_name
      assert_predicate owner.customer.billing_contact.first_name, :present?
      assert_predicate owner.customer.billing_contact.last_name, :present?
      assert_equal "foo", owner.customer.billing_contact.entity_name
    end

    test "syncs org screening profile that has first/last/entity name set to contact" do
      owner = create(:organization, customer: nil)
      owner.terms_of_service.update(type: "Corporate", actor: owner.admins.first)
      owner.disable_feature(:read_billing_information_from_contacts)
      assert_nil owner.customer

      # on create
      screening_profile = create(:account_screening_profile, :with_org, owner: owner, first_name: "foo", last_name: "bar")
      refute_nil owner.reload.customer
      assert_equal 1, owner.customer.contacts.size
      assert screening_profile.reload.metadata["migrated_to_contacts"]
      assert_equal "foo", screening_profile.first_name
      assert_equal "bar", screening_profile.last_name
      assert_predicate screening_profile.entity_name, :present?
      assert_equal "foo", owner.customer.billing_contact.first_name
      assert_equal "bar", owner.customer.billing_contact.last_name
      assert_predicate owner.customer.billing_contact.entity_name, :present?
    end

    test "syncs business screening profile that has first/last/entity name set to contact" do
      owner = create(:business, customer: nil)
      owner.disable_feature(:read_billing_information_from_contacts)
      assert_nil owner.customer

      # on create
      screening_profile = create(:account_screening_profile, :with_business, owner: owner, first_name: "foo", last_name: "bar")
      refute_nil owner.reload.customer
      assert_equal 1, owner.customer.contacts.size
      assert screening_profile.reload.metadata["migrated_to_contacts"]
      assert_equal "foo", screening_profile.first_name
      assert_equal "bar", screening_profile.last_name
      assert_predicate screening_profile.entity_name, :present?
      assert_equal "foo", owner.customer.billing_contact.reload.first_name
      assert_equal "bar", owner.customer.billing_contact.last_name
      assert_predicate owner.customer.billing_contact.entity_name, :present?
    end

    test "doesn't sync user screening profile that has blank PII set to contact" do
      owner = create(:user, customer: nil)
      owner.disable_feature(:read_billing_information_from_contacts)
      screening_profile = create(:account_screening_profile, owner: owner)
      refute_nil owner.reload.customer
      assert_equal 1, owner.customer.contacts.size
      assert screening_profile.reload.metadata["migrated_to_contacts"]
      assert_equal screening_profile.first_name, owner.customer.billing_contact.first_name

      # on update
      screening_profile.first_name = ""
      screening_profile.save!(validate: false)
      assert_predicate owner.reload.customer.billing_contact.first_name, :blank?

      # on update all PII to blank
      AccountScreeningProfile::PII_DATA_FIELDS.each do |field|
        screening_profile[field] = ""
      end

      screening_profile.save!(validate: false)
      refute_predicate owner.customer.billing_contact.last_name, :blank?
    end

    test "doesn't sync screening profile when read_billing_information_from_contacts is enabled" do
      owner = create(:user, customer: nil)
      owner.disable_feature(:read_billing_information_from_contacts)
      screening_profile = create(:account_screening_profile, owner: owner)
      refute_nil owner.reload.customer
      assert_equal 1, owner.customer.contacts.size
      assert screening_profile.reload.metadata["migrated_to_contacts"]
      assert_equal screening_profile.first_name, owner.customer.billing_contact.first_name

      # on update
      owner.enable_feature(:read_billing_information_from_contacts)
      screening_profile.first_name = ""
      screening_profile.save!(validate: false)
      refute_predicate owner.reload.customer.billing_contact.first_name, :blank?
    end

    test "reports error if syncing screening profile to contact fails" do
      owner = create(:business, :with_self_serve_payment)
      owner.disable_feature(:read_billing_information_from_contacts)
      customer = owner.customer
      shipping_contact = create(:shipping_contact, customer: customer)

      assert_equal 1, owner.customer.contacts.size
      screening_profile = create(:account_screening_profile, :with_business, owner: owner)
      assert_equal 2, owner.customer.contacts.size

      billing_contact = owner.customer.contacts.find { |contact| contact.billing? }
      fake_errors = stub(full_messages: %w(boom woof))
      Failbot.expects(:report).with(
        instance_of(AccountScreeningProfile::SyncToContactError),
        "gh.billing.contact.id": billing_contact.id,
        "gh.trade_compliance.trade_screening.external_id": screening_profile.external_uuid,
      ).once
      Billing::Contact.any_instance.stubs(:save).returns(false)
      Billing::Contact.any_instance.stubs(:errors).returns(fake_errors)
      screening_profile.update(entity_name: "Sparrows Inc.")
    end

    test "reports error if creating a new customer record fails" do
      mock_result = Minitest::Mock.new
      mock_result.expect(:success?, false)
      mock_result.expect(:error_message, "boom")
      mock_result.expect(:load, nil)
      mock_result.expect(:is_a?, true, [ActiveRecord::Relation])
      mock_create_customer = Minitest::Mock.new
      mock_create_customer.expect(:perform, mock_result)
      GitHub::Billing.expects(:create_customer_service).once.returns(mock_create_customer)

      user = create(:user)
      assert_nil user.customer
      user.enable_feature(:read_billing_information_from_contacts)
      user_screening_profile = create(:account_screening_profile, skip_contact_creation: true, owner: user)
      assert_nil user.reload.customer

      Failbot.expects(:report).with(
        instance_of(AccountScreeningProfile::CreateCustomerError),
        trade_screening_record_id: user_screening_profile.external_uuid,
        errors: "boom"
      ).once
      user.disable_feature(:read_billing_information_from_contacts)
      user_screening_profile.update(first_name: "Kudos")
    end

    test "doesn't sync screening profile to contact when the owner is a standard terms org" do
      owner = create(:credit_card_org)
      owner.disable_feature(:read_billing_information_from_contacts)
      customer = owner.customer

      screening_profile = create(:account_screening_profile, :with_org, owner: owner)
      assert_equal 0, owner.customer.contacts.size
    end
  end

  context "#valid_for_owner_type?" do
    test "returns true if screening record is valid for a specific owner type" do
      assert_predicate @user_with_screening_record.trade_screening_record, :valid_for_owner_type?
      assert_predicate @org_with_screening_record.trade_screening_record, :valid_for_owner_type?
      assert_predicate @business_with_screening_record.trade_screening_record, :valid_for_owner_type?
    end

    test "returns false if screening record is not valid for a specific owner type" do
      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(false)
      @user_with_screening_record.trade_screening_record.update(first_name: "")

      AccountScreeningProfile.any_instance.stubs(:entity_name_required?).returns(false)
      @org_with_screening_record.trade_screening_record.update(entity_name: "")
      @business_with_screening_record.trade_screening_record.update(entity_name: "")

      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(true)
      AccountScreeningProfile.any_instance.stubs(:entity_name_required?).returns(true)

      refute_predicate @user_with_screening_record.trade_screening_record, :valid_for_owner_type?
      refute_predicate @org_with_screening_record.trade_screening_record, :valid_for_owner_type?
      refute_predicate @business_with_screening_record.trade_screening_record, :valid_for_owner_type?

      refute_empty @user_with_screening_record.trade_screening_record.errors
      refute_empty @org_with_screening_record.trade_screening_record.errors
      refute_empty @business_with_screening_record.trade_screening_record.errors
    end

    test "returns false for user-owned partial records" do
      create(:account_screening_profile, :lic_r_enabled_and_no_hit, owner: @owner)

      assert_predicate @owner.trade_screening_record, :pseudo?
      refute_predicate @owner.trade_screening_record, :valid_for_owner_type?
    end

    test "returns false for business-owned partial records" do
      @org.terms_of_service.update(type: "Corporate", actor: @owner)
      create(:account_screening_profile, :with_org, :lic_r_enabled_and_no_hit, owner: @org)

      assert_predicate @org.trade_screening_record, :pseudo?
      refute_predicate @org.trade_screening_record, :valid_for_owner_type?
    end

    test "does not set errors hash on the record if skip_validation_errors is true" do
      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(false)
      @user_with_screening_record.trade_screening_record.update(first_name: "")

      AccountScreeningProfile.any_instance.stubs(:entity_name_required?).returns(false)
      @org_with_screening_record.trade_screening_record.update(entity_name: "")
      @business_with_screening_record.trade_screening_record.update(entity_name: "")

      AccountScreeningProfile.any_instance.stubs(:name_required?).returns(true)
      AccountScreeningProfile.any_instance.stubs(:entity_name_required?).returns(true)

      refute @user_with_screening_record.trade_screening_record.valid_for_owner_type?(skip_validation_errors: true)
      refute @org_with_screening_record.trade_screening_record.valid_for_owner_type?(skip_validation_errors: true)
      refute @business_with_screening_record.trade_screening_record.valid_for_owner_type?(skip_validation_errors: true)

      assert_empty @user_with_screening_record.trade_screening_record.errors
      assert_empty @org_with_screening_record.trade_screening_record.errors
      assert_empty @business_with_screening_record.trade_screening_record.errors
    end
  end

  context "#customer_details" do
    test "generates customer details from individual screening record" do
      personal_profile = create(:account_screening_profile)
      expected_customer_details = TradeCompliance::TradeScreening::CustomerDetails.new(
        id: "IndName_IndAddr",
        first_name: personal_profile.first_name,
        last_name: personal_profile.last_name,
        entity_name: personal_profile.entity_name,
        vat_code: personal_profile.vat_code,
        address1: personal_profile.address1,
        address2: personal_profile.address2,
        city: personal_profile.city,
        region: personal_profile.region,
        country_code: personal_profile.country_code,
        postal_code: personal_profile.postal_code,
      )

      customer_details = personal_profile.customer_details

      assert_customer_details_equal expected_customer_details, customer_details
    end

    test "generates customer details from organization screening record" do
      personal_profile = create(:account_screening_profile, :with_org)
      expected_customer_details = TradeCompliance::TradeScreening::CustomerDetails.new(
        id: "OrgName_OrgAddr",
        first_name: personal_profile.first_name,
        last_name: personal_profile.last_name,
        entity_name: personal_profile.entity_name,
        vat_code: personal_profile.vat_code,
        address1: personal_profile.address1,
        address2: personal_profile.address2,
        city: personal_profile.city,
        region: personal_profile.region,
        country_code: personal_profile.country_code,
        postal_code: personal_profile.postal_code,
      )

      customer_details = personal_profile.customer_details

      assert_customer_details_equal expected_customer_details, customer_details
    end
  end

  context "#screening_details" do
    test "generates screening details from individual screening record" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      personal_profile = create(:account_screening_profile)
      expected_screening_details = TradeCompliance::TradeScreening::ScreeningDetails.new(account_type: TradeCompliance::TradeScreening::AccountType::Individual, external_id: personal_profile.external_uuid)
      expected_customer_details = TradeCompliance::TradeScreening::CustomerDetails.new(
        id: "IndName_IndAddr",
        first_name: personal_profile.first_name,
        last_name: personal_profile.last_name,
        entity_name: personal_profile.entity_name,
        vat_code: personal_profile.vat_code,
        address1: personal_profile.address1,
        address2: personal_profile.address2,
        city: personal_profile.city,
        region: personal_profile.region,
        country_code: personal_profile.country_code,
        postal_code: personal_profile.postal_code,
      )
      expected_screening_details.add_customer_details(details: expected_customer_details)

      screening_details = personal_profile.screening_details

      assert_screening_details_equal expected_screening_details, screening_details
    end

    test "doesn't generate screening details from individual screening record when reading from contact is enabled" do
      GitHub.flipper[:read_billing_information_from_contacts].enable
      personal_profile = create(:account_screening_profile)
      expected_screening_details = TradeCompliance::TradeScreening::ScreeningDetails.new(account_type: TradeCompliance::TradeScreening::AccountType::Individual, external_id: personal_profile.external_uuid)

      screening_details = personal_profile.screening_details

      assert_screening_details_equal expected_screening_details, screening_details
    end

    test "generates screening details from organization screening record" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      personal_profile = create(:account_screening_profile, :with_org)
      expected_screening_details = TradeCompliance::TradeScreening::ScreeningDetails.new(account_type: TradeCompliance::TradeScreening::AccountType::Business, external_id: personal_profile.external_uuid)
      expected_customer_details = TradeCompliance::TradeScreening::CustomerDetails.new(
        id: "OrgName_OrgAddr",
        first_name: personal_profile.first_name,
        last_name: personal_profile.last_name,
        entity_name: personal_profile.entity_name,
        vat_code: personal_profile.vat_code,
        address1: personal_profile.address1,
        address2: personal_profile.address2,
        city: personal_profile.city,
        region: personal_profile.region,
        country_code: personal_profile.country_code,
        postal_code: personal_profile.postal_code,
      )
      expected_screening_details.add_customer_details(details: expected_customer_details)

      screening_details = personal_profile.screening_details

      assert_screening_details_equal expected_screening_details, screening_details
    end

    test "raises error if record is not persisted" do
      personal_profile = build(:account_screening_profile)

      assert_raises(AccountScreeningProfile::AccountScreeningProfileUpdateError) do
        screening_details = personal_profile.screening_details
      end
    end
  end

  context "#validate_billing_information_for_tax" do
    test "returns valid if billing address information is valid" do
      owner = create(:user, :verified)
      Billing::Public.expects(:validate_address).returns(valid_address_response)
      billing_info = build(:account_screening_profile, owner: owner, country_code: "US")
      response = billing_info.validate_billing_information_for_tax

      assert_predicate response, :valid
      assert_empty response.error
    end

    test "validates address if the billing address has not yet been validated" do
      owner = create(:user, :verified)
      Billing::Public.expects(:validate_address).returns(valid_address_response)
      billing_info = build(:account_screening_profile, owner: owner, country_code: "US")
      assert billing_info.billing_address_validated_at.blank?
      response = billing_info.validate_billing_information_for_tax

      assert_predicate response, :valid
      assert_empty response.error
    end

    test "returns error if billing address information is invalid" do
      owner = create(:user, :verified)
      billing_info = build(:account_screening_profile, owner: owner, country_code: "US")
      error_msg = "The address entered is invalid or cannot be found. Please make corrections and resave your billing information. Retrying with a 9-digit zip code may resolve the issue."
      Billing::Public.expects(:validate_address).returns(Billing::Public::AddressValidityResponse.new(valid: false, error: error_msg))
      response = billing_info.validate_billing_information_for_tax

      refute_predicate response, :valid
      assert_equal response.error, error_msg
    end

    test "returns error if there is a mismatch between supplied billing address and lookup response" do
      owner = create(:user, :verified)
      billing_info = build(:account_screening_profile, owner: owner, country_code: "US")
      error_msg = "The address entered did not match the postal code. Did you mean Greater Accra (suggested), OH (suggested)?"

      Billing::Public.expects(:validate_address).returns(Billing::Public::AddressValidityResponse.new(valid: false, error: error_msg))
      response = billing_info.validate_billing_information_for_tax
      refute_predicate response, :valid
      assert_equal response.error, error_msg
    end

    test "replaces postal code with suggested postal code from lookup response if there is postal code mismatch" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "US", last_trade_screen_date: Time.now.utc)
      original_postal_code = billing_info.postal_code

      assert_nil billing_info.billing_address_validated_at
      Billing::Public.expects(:validate_address).returns(valid_suggested_postal_code_address_response(suggested_postal_code: original_postal_code + "-1234"))

      owner.expects(:perform_live_sdn_screening).never
      response = billing_info.validate_billing_information_for_tax
      assert_equal billing_info.changed.sort, %w[postal_code billing_address_validated_at].sort
      assert_predicate response, :valid
      assert_empty response.error
      billing_info.save

      billing_info.reload
      assert_includes billing_info.postal_code, original_postal_code + "-1234"
      refute_nil billing_info.billing_address_validated_at
    end
  end

  context "#pseudo?" do
    test "returns false if the status is not_screened" do
      billing_info = create(:account_screening_profile)
      refute_predicate billing_info, :pseudo?
    end

    test "returns false if the record is not persisted" do
      billing_info = build(:account_screening_profile, msft_trade_screening_status: "no_hit")
      refute_predicate billing_info, :pseudo?
    end

    test "returns true if the record is persisted, with a valid status, but PII is incomplete" do
      billing_info = create(:account_screening_profile, :lic_r_enabled_and_no_hit)
      assert_predicate billing_info, :pseudo?
    end
  end

  context "#validated_for_sales_tax?" do
    test "returns true if country does not explicitly need to have their address validated (e.g. not United States)" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "GH")
      assert billing_info.validated_for_sales_tax?
    end

    test "returns true if country is United States and address is validated" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "US", billing_address_validated_at: Time.now)
      assert billing_info.validated_for_sales_tax?
    end

    test "returns false if country is United States and address isn't validated" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "US")
      refute billing_info.billing_address_validated_at
      refute billing_info.validated_for_sales_tax?
    end
  end

  context "#should_validate_for_tax?" do
    test "returns false if country is not United States" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "GH")
      refute billing_info.send(:should_validate_for_tax?)
    end

    test "returns false if none of the address fields has changed and the address has previously been validated" do
      owner = create(:user, :verified)

      billing_info = create(:account_screening_profile, owner: owner, country_code: "US")
      billing_info.billing_address_validated_at = GitHub::Billing.timezone.now
      assert billing_info.validated_for_sales_tax?

      billing_info.first_name = "John"
      refute billing_info.send(:should_validate_for_tax?)
    end

    test "returns true if the billing address has not been validated before" do
      owner = create(:user, :verified)

      billing_info = create(:account_screening_profile, owner: owner, country_code: "US")
      assert billing_info.billing_address_validated_at.blank?

      assert billing_info.send(:should_validate_for_tax?)
    end

    test "returns true if all the conditions are met" do
      owner = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: owner, country_code: "US")

      billing_info.address1 = "101 Strawberry Avenue"
      assert_predicate billing_info, :changed?
      assert billing_info.send(:should_validate_for_tax?)
    end
  end

  context "on update" do
    test "updates any linked organization's customer billing information and zuora account if pii data was saved" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      owner = create(:user, :verified)

      create(:customer_account, :zuora, user: owner)
      create(:billing_contact, customer: owner.customer)
      owner.customer.update!(
        name: "foobar",
        street_address: nil,
        postal_code: nil,
        country_code_alpha2: nil,
        region: nil,
        vat_code: nil,
      )

      billing_info = build(:account_screening_profile, owner: owner, vat_code: "vat")

      assert_enqueued_jobs 1, only: UpdateZuoraAccountInformationJob do
        billing_info.save!
      end

      org = create(:organization, admin: owner, plan: GitHub::Plan.free)
      create(:customer_account, :zuora, user: org)
      org.customer.update!(
        name: "foobar",
        street_address: nil,
        postal_code: nil,
        country_code_alpha2: nil,
        region: nil,
        vat_code: nil,
      )
      owner.link_trade_screening_record_to_org(organization: org)
      assert owner.has_trade_screening_record_linked_to_org?(organization: org)
      assert org.trade_screening_record.persisted?

      assert_enqueued_jobs 2, only: UpdateZuoraAccountInformationJob do
        billing_info.update!(
          address1: "101 Strawberry Avenue",
          postal_code: "12345",
        )
      end

      customer = owner.customer.reload

      assert_equal customer.name, billing_info.fullname
      assert_equal customer.street_address, billing_info.address1
      assert_equal customer.postal_code, billing_info.postal_code
      assert_equal customer.country_code_alpha2, billing_info.country_code
      assert_equal customer.region, billing_info.region
      assert_equal customer.vat_code, billing_info.vat_code

      org_customer = org.customer.reload
      assert_equal org_customer.name, billing_info.fullname
      assert_equal org_customer.street_address, billing_info.address1
      assert_equal org_customer.postal_code, billing_info.postal_code
      assert_equal org_customer.country_code_alpha2, billing_info.country_code
      assert_equal org_customer.region, billing_info.region
      assert_equal org_customer.vat_code, billing_info.vat_code
      assert_enqueued_with job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: org.customer.zuora_account_id, contact_id: owner.customer.billing_contact.id }]
    end

    test "enqueues job to sync vat_code if vat_code is created and customer exists" do
      owner = create(:user, :verified)
      create(:customer_account, :zuora, user: owner)

      assert_enqueued_jobs 1, only: SyncVatCodeJob do
        create(:account_screening_profile, owner: owner, vat_code: "vat")
      end
    end

    test "enqueues job to sync vat_code if vat_code is updated and customer exists" do
      owner = create(:user, :verified)
      create(:customer_account, :zuora, user: owner)
      trade_screening_record = create(:account_screening_profile, owner: owner, vat_code: "vat")

      assert_enqueued_jobs 1, only: SyncVatCodeJob do
        trade_screening_record.update!(vat_code: "vat2")
      end
    end
  end

  context "#destroy" do
    test "when destroying a screening record linked to an SToS org it also removes the references" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin, plan: GitHub::Plan.free)

      assert admin.has_saved_trade_screening_record?
      admin.link_trade_screening_record_to_org(organization: org)
      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
      assert org.trade_screening_record.persisted?

      admin.trade_screening_record.destroy

      admin.reload
      org.reload

      refute admin.has_saved_trade_screening_record?
      refute admin.has_trade_screening_record_linked_to_org?(organization: org)
      refute org.trade_screening_record.persisted?
    end

    test "when destroying a screening record it also removes the associated payment method" do
      user = create(:credit_card_user, :with_valid_contact_for_billing)

      assert_predicate user, :has_saved_trade_screening_record?
      assert_predicate user, :has_valid_payment_method?

      user.trade_screening_record.destroy
      user.reload

      refute_predicate user, :has_saved_trade_screening_record?
      refute_predicate user, :has_valid_payment_method?
    end
  end

  context "send_llama2_access_request" do
    test "does not send Llama v2 access request to hydro if msft_trade_screening_status is updated and status is hit_in_review" do
      user = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: user)
      billing_info.update(metadata: { llama2_access: { dwh_data_sent: false } })
      billing_info.hit_in_review!

      refute_hydro_messages(schema: "github.trade_screening.v0.Llama2Request")

      updated_billing_info = user.reload.trade_screening_record
      assert updated_billing_info.metadata["llama2_access"]["dwh_data_sent"] == false # unchanged
    end

    test "does not send Llama v2 access request to hydro if msft_trade_screening_status is updated but user has not requested access" do
      user = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: user)
      billing_info.no_hit!

      refute_hydro_messages(schema: "github.trade_screening.v0.Llama2Request")
    end

    test "does not send Llama v2 access request to hydro if msft_trade_screening_status is updated but data has already been sent" do
      user = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: user)
      billing_info.update(metadata: { llama2_access: { dwh_data_sent: true } })
      billing_info.no_hit!

      refute_hydro_messages(schema: "github.trade_screening.v0.Llama2Request")

      updated_billing_info = user.reload.trade_screening_record
      assert updated_billing_info.metadata["llama2_access"]["dwh_data_sent"] == true # unchanged
    end

    test "sends Llama v2 access request to hydro if msft_trade_screening_status is updated and status is not hit_in_review" do
      user = create(:user, :verified)
      billing_info = create(:account_screening_profile, owner: user)
      billing_info.update(metadata: { llama2_access: { dwh_data_sent: false } })
      billing_info.no_hit!

      assert_hydro_published({
        user_login: user.display_login,
        user_id: user.id,
        approval_status: "APPROVED",
        external_user_id: billing_info.external_uuid,
      }, schema: "github.trade_screening.v0.Llama2Request")

      updated_billing_info = user.reload.trade_screening_record
      assert updated_billing_info.metadata["llama2_access"]["dwh_data_sent"] == true
    end
  end

  context "last_trade_screen_date" do
    test "updates last_trade_screen_date if msft_trade_screening_status is updated" do
      upp = create(:account_screening_profile)
      assert_nil upp.last_trade_screen_date
      current_time = Time.new(2020, 11, 25, 1, 0, 0).utc

      Timecop.freeze(current_time) do
        upp.update(msft_trade_screening_status: "hit_in_review")
      end

      upp.reload
      assert_equal upp.last_trade_screen_date, current_time
    end

    test "last_trade_screen_date_less_than_2_days_ago returns true when last_trade_screen_date is newer than 2 days ago" do
      user = create(:credit_card_user, :verified)
      create(:account_screening_profile, last_trade_screen_date: 1.day.ago, overdue_email: :not_sent, owner: user)
      assert_predicate user.trade_screening_record, :last_trade_screen_date_less_than_2_days_ago?
    end

    test "last_trade_screen_date_less_than_2_days_ago returns false when last_trade_screen_date is older than 2 days ago" do
      user = create(:credit_card_user, :verified)
      create(:account_screening_profile, last_trade_screen_date: 3.days.ago, overdue_email: :not_sent, owner: user)
      refute_predicate user.trade_screening_record, :last_trade_screen_date_less_than_2_days_ago?
    end

    test "last_trade_screen_date_less_than_7_days_ago returns true when last_trade_screen_date is less than or equal to 7 days ago" do
      user = create(:credit_card_user, :verified)
      create(:account_screening_profile, last_trade_screen_date: 6.days.ago, overdue_email: :not_sent, owner: user)
      assert_predicate user.trade_screening_record, :last_trade_screen_date_less_than_7_days_ago?
    end

    test "last_trade_screen_date_less_than_7_days_ago returns false when last_trade_screen_date is greater than 7 days ago" do
      user = create(:credit_card_user, :verified)
      create(:account_screening_profile, last_trade_screen_date: 8.days.ago, overdue_email: :not_sent, owner: user)
      refute_predicate user.trade_screening_record, :last_trade_screen_date_less_than_7_days_ago?
    end

    test "last_trade_screen_date_older_than_7_days_ago returns true when last_trade_screen_date is greater 7 days ago" do
      user = create(:credit_card_user, :verified)
      create(:account_screening_profile, last_trade_screen_date: 8.days.ago, overdue_email: :not_sent, owner: user)
      assert_predicate user.trade_screening_record, :last_trade_screen_date_older_than_7_days_ago?
    end

    test "updating last_trade_screen_date or msft_trade_screening_status does not trigger rescreen" do
      upp = create(:account_screening_profile)
      user = upp.user

      user.enable_feature(:live_sdn_screening)

      assert_nil upp.last_trade_screen_date
      current_time = Time.new(2020, 11, 25, 1, 0, 0).utc

      Timecop.freeze(current_time) do
        upp.update(msft_trade_screening_status: "no_hit")
      end

      upp.reload
      assert_equal upp.last_trade_screen_date, current_time

      # If screening was done and an error occurred because we are not mocking the screening API call,
      # we would have a status of `retry`. Here, we should have the same status as before since no screening is done.
      assert_equal upp.msft_trade_screening_status, "no_hit"
    end

    test "does not update last_trade_screen_date if msft_trade_screening_status is not updated" do
      upp = create(:account_screening_profile)
      assert_nil upp.last_trade_screen_date

      upp.update(first_name: "Kofi")
      upp.reload
      assert_nil upp.last_trade_screen_date
    end
  end

  context "fullname" do
    test "creates a full name out of the first, middle and last names available" do
      personal_profile = create(:account_screening_profile, first_name: "Mona", middle_name: "Lisa", last_name: "Laziza")
      assert_equal personal_profile.fullname, "Mona Lisa Laziza"
    end

    test "creates a full name out of the first and last name without middle double spaces" do
      personal_profile = create(:account_screening_profile, first_name: "Mona", last_name: "Lisa")
      assert_equal personal_profile.fullname, "Mona Lisa"
    end
  end

  context "instrument" do
    test "instrument create when a account_screening_profile have been created" do
      events = subscribe "account_screening_profile.create"
      create(:account_screening_profile)
      assert events.pop
    end

    test "instruments create with org_id when an account_screening_profile has been created for org" do
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.create") do
        create(:account_screening_profile, :with_org)
      end

      assert events.first.has_key?(:org_id)
      refute_nil events.first[:org_id]
    end

    test "instruments create when an account_screening_profile has been created for business" do
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.create") do
        create(:account_screening_profile, :with_business)
      end

      assert events.first.has_key?(:business_id)
      refute_nil events.first[:business_id]
    end

    test "instrument update when a account_screening_profile have been updated" do
      events = subscribe "account_screening_profile.update"
      account_screening_profile = create(:account_screening_profile)
      account_screening_profile.update(first_name: "Monalisa")
      assert events.pop
    end

    test "instruments update with org_id when an account_screening_profile has been updated for org" do
      account_screening_profile = create(:account_screening_profile, :with_org)
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.update") do
        account_screening_profile.no_hit!
      end

      assert events.first.has_key?(:org_id)
      refute_nil events.first[:org_id]
    end

    test "instruments update when an account_screening_profile has been updated for business" do
      events = subscribe "account_screening_profile.update"
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.update(entity_name: "Monalisa Inc.")
      assert events.pop
    end

    test "instrument destroy when a account_screening_profile has been destroyed" do
      personal_profile = create(:account_screening_profile)
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.destroy") do
        personal_profile.destroy(actor: @staff, reason: "GDPR delete")
      end

      expected_payload = {
        action: "account_screening_profile.destroy",
        user_id: personal_profile.owner_id,
        user: personal_profile.user.login,
        actor: @staff.login,
        operation_type: "remove",
        reason: "GDPR delete",
        external_uuid: personal_profile.external_uuid,
      }

      event = events.pop
      assert_subset_hash expected_payload, event
      assert personal_profile.destroyed?
    end

    test "instruments destroy with org_id when an account_screening_profile has been destroyed for org" do
      account_screening_profile = create(:account_screening_profile, :with_org)
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.destroy") do
        account_screening_profile.destroy(actor: @staff, reason: "GDPR delete")
      end

      assert events.first.has_key?(:org_id)
      refute_nil events.first[:org_id]
    end

    test "instruments screening when a account_screening_profile's msft_screening_status has been updated" do
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
        account_screening_profile = create(:account_screening_profile, owner: @owner)
        account_screening_profile.no_hit!
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "account_screening_profile.live_sdn_screening",
        user_id: @owner.id,
        user: @owner.login,
        screening_status: "no_hit",
        operation_type: "modify",
        external_uuid: @owner.trade_screening_record.external_uuid,
      }

      event = events.pop
      assert_subset_hash expected_payload, event
      assert_nil event[:changed_attributes]
    end

    test "instruments screening when an account_screening_profile's pii has been updated" do
      GitHub.flipper[:live_sdn_screening].enable
      account_screening_profile = create(:account_screening_profile, :with_populated_attributes)
      Timecop.travel(10.minutes.ago) do
        account_screening_profile.no_hit!
      end
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
        account_screening_profile.update(first_name: "Monalisa")
      end

      update_event = events.first
      assert update_event.has_key?(:changed_attributes)
      assert_equal "first_name", update_event[:changed_attributes]
    end

    test "instruments screening with status reason when an account_screening_profile's msft_screening_status is updated to retry" do
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
        account_screening_profile = create(:account_screening_profile, owner: @owner)
        account_screening_profile.update(msft_trade_screening_status: "retry", metadata: { status_reason: "oops" })
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "account_screening_profile.live_sdn_screening",
        user_id: @owner.id,
        user: @owner.login,
        screening_status: "retry",
        status_reason: "oops",
        operation_type: "modify",
        external_uuid: @owner.trade_screening_record.external_uuid,
      }

      event = events.pop
      assert_subset_hash expected_payload, event
      assert_nil event[:changed_attributes]
    end

    test "instruments screening with status reason when an account_screening_profile's msft_screening_status is updated to error" do
      events = assert_performed_audit_entries(count: 1, only: "account_screening_profile.live_sdn_screening") do
        account_screening_profile = create(:account_screening_profile, owner: @owner)
        account_screening_profile.update(msft_trade_screening_status: "error", metadata: { status_reason: "oops" })
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "account_screening_profile.live_sdn_screening",
        user_id: @owner.id,
        user: @owner.login,
        screening_status: "error",
        status_reason: "oops",
        operation_type: "modify",
        external_uuid: @owner.trade_screening_record.external_uuid,
      }

      event = events.pop
      assert_subset_hash expected_payload, event
      assert_nil event[:changed_attributes]

      assert_dogstats_increment(1, "sdn.status.error", tags: ["status_reason:oops"])
    end
  end

  if GitHub.billing_enabled?
    context "sync with business customer" do
      test "does not write information to business customer when no PII change" do
        profile = create(:account_screening_profile, :with_self_serve_business, :with_populated_attributes, msft_trade_screening_status: "hit_in_review")
        Customer.any_instance.expects(:update_from_account_screening_record).never
        profile.update(msft_trade_screening_status: "no_hit")
      end

      test "writes information to business customer when PII change" do
        profile = create(:account_screening_profile, :with_self_serve_business, :with_populated_attributes, msft_trade_screening_status: "no_hit")
        Customer.any_instance.expects(:update_from_account_screening_record)
        profile.update(region: "Neo Tokyo 3")
      end

      test "does not write information to business customer until screening is completed with an allowed status and PII is changed" do
        Customer.any_instance.expects(:update_from_account_screening_record).never
        profile = create(:account_screening_profile, :with_self_serve_business, :with_populated_attributes, :not_screened)
        profile.update(msft_trade_screening_status: "no_hit")
        Customer.any_instance.expects(:update_from_account_screening_record).once
        profile.update(region: "Neo Tokyo 3")
      end

      test "does not write information to business customer when hit in review" do
        Customer.any_instance.expects(:update_from_account_screening_record).never
        profile = create(:account_screening_profile, :with_business, :with_populated_attributes, :hit_in_review)
      end

      test "writes information to business customer when the business is eligible for self-serve payments" do
        GitHub.flipper[:read_billing_information_from_contacts].disable
        profile = create(:account_screening_profile, :with_self_serve_business, :with_populated_attributes, msft_trade_screening_status: "no_hit")
        business = profile.business
        customer = business.customer
        assert_equal profile.entity_name, customer.name
        assert_equal profile.address1, customer.street_address
        assert_equal profile.postal_code, customer.postal_code
        assert_equal profile.country_code, customer.country_code_alpha2
        assert_equal profile.region, customer.region
        assert_equal profile.vat_code, customer.vat_code
      end
    end
  end

  context "status change callbacks" do
    test "updates the account screening profile status" do
      upp = create(:account_screening_profile, :hit_in_review)

      upp.update(msft_trade_screening_status: "no_hit")

      assert upp.no_hit?
    end

    test "allow email is sent when a user goes from hit_in_review to an allowed status and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "previous_status:hit_in_review",
        "current_status:no_hit",
      ]

      upp = create(:account_screening_profile, :hit_in_review)
      upp.user.expects(:send_trade_controls_allowed_status_email)
      upp.user.expects(:send_trade_controls_not_allowed_status_email).never

      upp.update(msft_trade_screening_status: "no_hit")

      assert_equal 1, stats.increments("sdn.status.to_allowed_to_update", tags: expected_tags).count
    end

    test "update information email is sent when a user goes from hit_in_review to data_issue and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "previous_status:hit_in_review",
        "current_status:data_issue",
      ]

      upp = create(:account_screening_profile, :hit_in_review)
      upp.user.expects(:send_trade_controls_data_needs_fixing_status_email)
      upp.user.expects(:send_trade_controls_allowed_status_email).never
      upp.user.expects(:send_trade_controls_not_allowed_status_email).never

      upp.update(msft_trade_screening_status: "data_issue")

      assert_equal 1, stats.increments("sdn.status.to_allowed_to_update", tags: expected_tags).count
    end

    test "not allowed email is sent when user goes from hit_in_review to a not allowed status and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      expected_tags = [
        "previous_status:hit_in_review",
        "current_status:lic_r",
      ]

      upp = create(:account_screening_profile, :hit_in_review)
      upp.user.expects(:send_trade_controls_not_allowed_status_email)
      upp.user.expects(:send_trade_controls_allowed_status_email).never

      upp.update(msft_trade_screening_status: "lic_r")

      assert_equal 1, stats.increments("sdn.status.to_not_allowed_to_update", tags: expected_tags).count
    end

    test "email is not sent when a user goes from hit_in_review to a true_match status" do
      upp = create(:account_screening_profile, :hit_in_review)
      upp.user.expects(:send_trade_controls_allowed_status_email).never
      upp.user.expects(:send_trade_controls_not_allowed_status_email).never

      upp.update(msft_trade_screening_status: "true_match")
    end

    test "email is not sent when a user is not going from hit_in_review" do
      upp = create(:account_screening_profile, msft_trade_screening_status: "not_screened")
      upp.user.expects(:send_trade_controls_allowed_status_email).never
      upp.user.expects(:send_trade_controls_not_allowed_status_email).never

      upp.update(msft_trade_screening_status: "no_hit")
    end

    test "doesn't send notify email when user was not hit_in_review and receives an allowed status" do
      upp = create(:account_screening_profile)

      upp.user.expects(:send_trade_controls_allowed_status_email).never
      upp.user.expects(:send_trade_controls_not_allowed_status_email).never

      upp.update(msft_trade_screening_status: "lic_a")
    end
  end

  if GitHub.sponsors_enabled?
    test "user with approved sponsors listing has their Sponsors listing disabled when receiving a hit_in_review screening status" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      profile = create(:account_screening_profile, :not_screened, :with_approved_sponsors_listing)
      user = profile.user
      sponsors_listing = user.sponsors_listing
      user.enable_feature(:live_sdn_screening)

      # Is everything as expected?
      assert_predicate profile, :not_screened?
      assert_predicate sponsors_listing, :approved?

      perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
        # receive blocking status
        profile.hit_in_review!
      end

      # Has the listing been sdn_disabled?
      assert_predicate sponsors_listing.reload, :sdn_disabled?

      assert_equal 1, stats.increments("sponsors_listing.sdn_disable").count
    end

    %w[ssi_d ssi_e ssi_f lic_r no_hit not_screened ssi_d_30 ssi_e_60 ssi_f_14 lic_a].each do |sdn_screening_status|
      test "an approved listing still remains approved after receiving a blocking screening status as long as the screening status received is not hit_in_review. Eg. #{sdn_screening_status} status" do
        profile = create(:account_screening_profile, :not_screened, :with_approved_sponsors_listing)
        user = profile.user
        sponsors_listing = user.sponsors_listing
        user.enable_feature(:live_sdn_screening)

        # Is everything as expected?
        assert_predicate profile, :not_screened?
        assert_predicate sponsors_listing, :approved?

        perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
          # receive blocking status
          profile.public_send("#{sdn_screening_status}!")
        end

        # Has the listing been sdn_disabled?
        assert_predicate sponsors_listing.reload, :approved?
      end
    end

    %w[ssi_d ssi_e ssi_f lic_r no_hit not_screened ssi_d_30 ssi_e_60 ssi_f_14 lic_a].each do |sdn_screening_status|
      test "user with a blocking screening status has their Sponsors listing enabled when getting #{sdn_screening_status}" do
        profile = create(:account_screening_profile, :with_sdn_disabled_sponsors_listing)
        profile.public_send("hit_in_review!")

        user = profile.user
        sponsors_listing = user.sponsors_listing
        user.enable_feature(:live_sdn_screening)

        # Is everything as expected?
        assert_predicate profile, :hit_in_review?
        assert_predicate sponsors_listing, :sdn_disabled?

        perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
          # receive unblocking status
          profile.public_send("#{sdn_screening_status}!")
        end

        # Has the listing been approved?
        assert_predicate sponsors_listing.reload, :approved?
      end
    end

    test "user with a blocking screening status does not get their Sponsors listing enabled when getting true_match status" do
      profile = create(:account_screening_profile, :with_sdn_disabled_sponsors_listing)
      profile.public_send("hit_in_review!")

      user = profile.user
      sponsors_listing = user.sponsors_listing
      user.enable_feature(:live_sdn_screening)

      # Is everything as expected?
      assert_predicate profile, :hit_in_review?
      assert_predicate sponsors_listing, :sdn_disabled?

      perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
        # receive true match status
        profile.public_send("true_match!")
      end

      # Has the listing been approved?
      assert_predicate sponsors_listing.reload, :sdn_disabled?
    end

    test "no operation on sponsors_listing when user with a blocking screening status gets a blocking status" do
      profile = create(:account_screening_profile, :hit_in_review, :with_sdn_disabled_sponsors_listing)
      user = profile.user
      sponsors_listing = user.sponsors_listing
      user.enable_feature(:live_sdn_screening)

      # Is everything as expected?
      assert_predicate profile, :hit_in_review?
      assert_predicate sponsors_listing, :sdn_disabled?

      perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
        # receive another blocking status
        profile.hit_in_review!
      end

      # Sponsor listing has not changed
      assert_predicate sponsors_listing.reload, :sdn_disabled?
    end

    test "no action on sponsors_listing when the listing is not approved even with the user having a blocking status" do
      profile = create(:account_screening_profile, :not_screened, :with_draft_sponsors_listing)
      user = profile.user
      sponsors_listing = user.sponsors_listing
      user.enable_feature(:live_sdn_screening)

      # Is everything as expected?
      assert_predicate profile, :not_screened?
      assert_predicate sponsors_listing, :draft?

      sponsors_listing.expects(:sdn_disable!).never
      perform_enqueued_jobs(only: [TradeControls::Sdn::EnableOrDisableMaintainerJob]) do
        # receive blocking status
        profile.hit_in_review!
      end
    end
  end

  context "sdn compliance" do
    test "if an account is marked as true match then it should be not suspended if flag is disabled" do
      @owner.disable_feature(:live_sdn_screening)
      personal_profile = create(:account_screening_profile, owner: @owner)
      personal_profile.true_match!
      refute_equal @owner.suspended?, true
      refute @owner.legal_hold?
    end

    test "if an account is marked as true match it suspends the account and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      @owner.enable_feature(:live_sdn_screening)
      personal_profile = create(:account_screening_profile, owner: @owner)
      repository = create(:repository, owner: @owner)
      private_repo = create(:private_repository, owner: @owner)

      @owner.sdn_suspend(staff_user: @staff, reason: "reason")
      repository.reload
      private_repo.reload
      repository.delete

      assert_equal @owner.suspended?, true
      assert @owner.legal_hold?
      refute repository.deleted?
      refute_predicate repository, :locked?
      assert_predicate private_repo, :locked?
      assert_predicate repository, :archived?
      refute_predicate private_repo, :archived?
      assert_equal 1, stats.increments("sdn.true_match.suspension.success").count
    end

    test "if an account is marked as true match it doesn't automatically suspend" do
      @owner.enable_feature(:live_sdn_screening)
      create(:user, login: "hubot")

      personal_profile = create(:account_screening_profile, owner: @owner)
      personal_profile.true_match!

      refute @owner.suspended?
    end

    test "if an account is marked as true match it adds a staff note to the account" do
      @owner.enable_feature(:live_sdn_screening)
      create(:user, login: "hubot")

      personal_profile = create(:account_screening_profile, owner: @owner)
      @owner.sdn_suspend(staff_user: @staff, reason: "reason")

      assert @owner.suspended?
      assert @owner.legal_hold?
      assert @owner.staff_notes.any?
      assert_equal "DO NOT MODIFY THIS ACCOUNT WITHOUT APPROVAL FROM TRADE SUPPORT/CELA. reason", @owner.staff_notes.last.body
    end

    test "if an account is marked as true match with a reason then it should be saved instead of default reason" do
      @owner.enable_feature(:live_sdn_screening)

      personal_profile = create(:account_screening_profile, owner: @owner)
      personal_profile.metadata = personal_profile.metadata.merge(status_reason: "reason")

      events = assert_performed_audit_entries(count: 1, only: "user.suspend") do
        @owner.sdn_suspend(staff_user: @staff, reason: "reason")
      end

      assert event = events.pop, "a user.suspend event was expected"
      assert_equal "reason", event[:reason]

      assert @owner.suspended?
      assert_equal "#{TradeControls::AbstractTradeScreeningDependency::STAFF_ACTION}reason", personal_profile.metadata["status_reason"]
    end

    test "if an account is marked as true match, it notifies the Security & Revenue Support team" do
      personal_profile = create :account_screening_profile, owner: @owner

      TradeControls::LegalNotification
        .expects(:create_for_true_match_account)
        .once
        .with(account: @owner)

      # this should notify the Legal Support team
      personal_profile.true_match!

      # this shouldn't notify the Legal Support team
      @owner.sdn_suspend(staff_user: @staff, reason: "reason")
    end

    test "if a sponsors maintainer is marked as true match, it notifies the Legal Support team" do
      @owner.enable_feature(:live_sdn_screening)
      create :sponsors_listing, sponsorable: @owner
      personal_profile = create :account_screening_profile, owner: @owner

      TradeControls::LegalNotification
        .expects(:create_for_sponsors_maintainer)
        .once
        .with(account: @owner)

      @owner.sdn_suspend(staff_user: @staff, reason: "reason")
    end

    test "if a non sponsors maintainer is marked as true match, no notification for sponsors is created" do
      @owner.enable_feature(:live_sdn_screening)
      personal_profile = create :account_screening_profile, owner: @owner

      TradeControls::LegalNotification
        .expects(:create_for_sponsors_maintainer)
        .never

      personal_profile.true_match!
    end

    test "if an account is marked as true match for a Hammy user it suspends the user" do
      @owner.enable_feature(:live_sdn_screening)
      @owner.mark_as_hammy
      assert_equal @owner.hammy?, true
      personal_profile = create(:account_screening_profile, owner: @owner)

      @owner.sdn_suspend(staff_user: @staff, reason: "reason")

      assert_predicate @owner, :suspended?
      assert_predicate @owner, :legal_hold?
    end

    test "if an account moves out of true_match status into true_match, suspension is not removed" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      @owner.enable_feature(:live_sdn_screening)

      personal_profile = create(:account_screening_profile, owner: @owner, msft_trade_screening_status: "true_match")
      @owner.suspend("Suspending for test")
      assert_predicate @owner, :suspended?
      personal_profile.public_send("true_match!")

      assert_predicate @owner, :suspended?
    end

    test "if an account moves out of other status than true_match, unsuspension does not run" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      @owner.enable_feature(:live_sdn_screening)

      personal_profile = create(:account_screening_profile, owner: @owner, msft_trade_screening_status: "no_hit")
      @owner.suspend("Suspending for test")
      @owner.spammy = true
      assert_predicate @owner, :spammy?
      assert_predicate @owner, :suspended?
      personal_profile.public_send("lic_r!")

      # User is still spammy and suspended
      assert_predicate @owner, :spammy?
      assert_predicate @owner, :suspended?
    end

    test "if an account moves out of true_match status but previously not suspended, a log message is added indicating inconsistent state" do
      GitHub::Turboscan::ManagedAnalyses.stubs(:get_managed_analysis_info).returns(nil)
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      @owner.enable_feature(:live_sdn_screening)

      personal_profile = create(:account_screening_profile, owner: @owner, msft_trade_screening_status: "true_match")
      repository = create(:repository, owner: @owner)
      @owner.mark_as_spammy
      @owner.reload
      assert_predicate @owner, :spammy?
      refute_predicate repository, :archived?
      personal_profile.public_send("no_hit!")
      repository.reload

      refute_predicate @owner, :spammy?
      refute_predicate @owner, :suspended?
      assert_equal 1, stats.increments("sdn.true_match.unsuspension.mismatch").count
      report = Failbot.reports.last
      assert_equal "True match screening profile was not suspended", Failbot.exception_message_from_hash(report)
      refute_predicate personal_profile, :true_match?
      refute_predicate repository, :archived?
    end

    test "if an account moves out of true_match but unsuspension fails it raises an exception and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)
      @owner.enable_feature(:live_sdn_screening)
      @owner.stubs(:unsuspend).returns(false)

      personal_profile = create(:account_screening_profile, owner: @owner, msft_trade_screening_status: "true_match")
      @owner.suspend("Suspending for test")
      assert_predicate @owner, :suspended?
      assert_raises(AccountScreeningProfile::AccountScreeningProfileUpdateError) do
        personal_profile.public_send("no_hit!")
      end
      assert_predicate @owner, :suspended?
      assert_equal 1, stats.increments("sdn.true_match.unsuspension.failed").count
    end

    test "if an account moves out of true match it unlocks repos with billing lock" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      @owner.enable_feature(:live_sdn_screening)
      personal_profile = create(:account_screening_profile, owner: @owner, msft_trade_screening_status: "true_match", metadata: { status_reason: "MT" })
      repository = create(:repository, owner: @owner)
      private_repo = create(:private_repository, owner: @owner)
      private_repo2 = create(:private_repository, owner: @owner)

      private_repo.lock_excluding_descendants!(Repository::LockDependency::BILLING)
      private_repo2.lock_excluding_descendants!(Repository::LockDependency::RENAME)

      refute_empty personal_profile.metadata["status_reason"]

      personal_profile.no_hit!

      private_repo.reload
      private_repo2.reload
      repository.reload
      @owner.reload

      assert_equal @owner.suspended?, false
      refute @owner.legal_hold?
      refute_predicate private_repo, :locked?
      assert_predicate private_repo2, :locked?
      refute_predicate repository, :archived?
      refute_predicate private_repo, :archived?
      assert_equal 1, stats.increments("sdn.true_match.unsuspension.success").count
      assert_nil personal_profile.metadata["status_reason"]
      assert_equal "User was moved out of true match in the SDN database", @owner.staff_notes.last.body
    end

    %w[old_method new_method].each do |method|
      test "if an org moves out of true match it successfully unsuspends if org was previously suspended using the #{method}" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        is_new_method = method == "new_method"
        @org.enable_feature(:sdn_organization_suspension_v3) if is_new_method
        @org.disable_feature(:sdn_organization_suspension_v3) if !is_new_method

        reason = "bad actor"
        create_list(:private_repository, 2, owner: @org)
        create_list(:repository, 2, owner: @org)
        @org.sdn_suspend(staff_user: User.staff_user, reason: reason)
        @org.reload

        assert_predicate @org, :sdn_suspended?
        @org.repositories.each do |repository|
          if repository.private?
            assert_predicate repository, :locked_on_trade_restriction? if is_new_method
            assert repository.disabled?(viewer: @org.admins.first) if !is_new_method
          else
            assert_predicate repository, :archived?
          end
        end
        screening_record = @org.trade_screening_record
        assert_equal screening_record.metadata["status_reason"], "Staff action: #{reason}"

        screening_record.no_hit!
        @org.reload

        refute_predicate @org, :sdn_suspended?
        @org.repositories.each do |repository|
          if repository.private?
            refute_predicate repository, :locked_on_trade_restriction? if is_new_method
            refute repository.disabled?(viewer: @org.admins.first)
          else
            refute_predicate repository, :archived?
          end
        end
        assert_nil @org.trade_screening_record.metadata["status_reason"]
        assert_equal "User was moved out of true match in the SDN database", @org.staff_notes.last.body
      end
    end

    test "if an account is marked as true match and account suspension fails it raises an exception and reports to dogstats" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      expected_tags = [
        "reason: User was a true match hit in the SDN database, however, suspension failed.",
      ]

      @owner.enable_feature(:live_sdn_screening)
      @owner.stubs(:suspend).returns(false)
      personal_profile = create(:account_screening_profile, owner: @owner)
      assert_raises AccountScreeningProfile::AccountScreeningProfileUpdateError do
        @owner.sdn_suspend(staff_user: @staff, reason: "User was a true match hit in the SDN database")
      end

      refute_predicate @owner, :suspended?
      refute_predicate @owner, :legal_hold?
      assert_equal 1, stats.increments("sdn.true_match.suspension.failed", tags: expected_tags).count
    end

    test "doesn't allow updating non screening status field when having restricted status" do
      personal_profile = create(:account_screening_profile, :hit_in_review)
      personal_profile.user.enable_feature(:live_sdn_screening)

      refute personal_profile.update(first_name: "Joker")

      assert_predicate personal_profile.errors[:updates_restricted], :present?
    end

    %w[ingestion_error data_issue].each do |sdn_screening_status|
      test "does not raise on updating non screening status field when having #{sdn_screening_status} status " do
        personal_profile = create(:account_screening_profile)
        personal_profile.public_send("#{sdn_screening_status}!")
        personal_profile.user.enable_feature(:live_sdn_screening)

        personal_profile.update(first_name: "Joker")
      end
    end

    test "does not raise on updating screening status field when having restricted status " do
      personal_profile = create(:account_screening_profile)
      personal_profile.hit_in_review!
      personal_profile.user.enable_feature(:live_sdn_screening)

      assert personal_profile.no_hit!
      assert_equal personal_profile.msft_trade_screening_status.to_sym, :no_hit
    end

    %w[hit_in_review true_match].each do |sdn_screening_status|
      test "destroy is blocked when in #{sdn_screening_status} SDN status" do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: sdn_screening_status)

        assert_raises_with_message AccountScreeningProfile::AccountScreeningProfileDeleteError, "Current SDN status does not allow personal profile deletion" do
          personal_profile.destroy!
        end

        refute_predicate personal_profile, :destroyed?
      end
    end

    test "BillingChangesJob is not queued upon creation with status not_screened" do
      assert_no_enqueued_jobs only: TradeControls::Sdn::BillingChangesJob do
        personal_profile = create(:account_screening_profile)
      end
    end

    test "BillingChangesJob is queued when status changes to not_screened" do
      personal_profile = T.let(nil, T.untyped)
      perform_enqueued_jobs only: TradeControls::Sdn::BillingChangesJob do
        personal_profile = create(:account_screening_profile, :no_hit)
      end

      assert_enqueued_jobs 1, only: TradeControls::Sdn::BillingChangesJob do
        personal_profile.not_screened!
      end
    end

    test "BillingChangesJob is queued upon creation with status other than not_screened" do
      assert_enqueued_jobs 1, only: TradeControls::Sdn::BillingChangesJob do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: "lic_r")
      end
    end

    test "destroy is not blocked when in non-restrictive SDN status" do
      personal_profile = create(:account_screening_profile, msft_trade_screening_status: "lic_r")

      TradeControls::Sdn::BillingChangesJob.expects(:perform_now).once
      personal_profile.destroy!

      assert_predicate personal_profile, :destroyed?
    end

    test "a private repo locked on trade restriction reason during suspension is unlocked during unsuspension" do
      owner = create(:user, :verified)
      private_repo = create(:private_repository, owner: owner)

      create(:account_screening_profile, :true_match, owner: owner)
      owner.sdn_suspend(staff_user: @staff, reason: "reason")

      assert owner.sdn_suspended?
      assert private_repo.reload.locked_on_trade_restriction?

      owner.trade_screening_record.no_hit!

      private_repo.reload
      owner.reload

      refute owner.sdn_suspended?
      refute private_repo.locked?
      refute private_repo.locked_on_trade_restriction?
    end
  end

  context "allowed_auto_sponsorship?" do
    TradeControls::SdnScreeningTestHelper::NOT_ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns false when a account screening profile has a screening status of #{status}" do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: status)
        refute personal_profile.allowed_auto_sponsorship?
      end
    end

    TradeControls::SdnScreeningTestHelper::ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "returns true when a account screening profile has a screening status of #{status}" do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: status)
        assert personal_profile.allowed_auto_sponsorship?
      end
    end
  end

  context "temporary_status?" do
    TradeControls::SdnScreeningTestHelper::SDN_TEMPORARY_STATUSES.each do |status|
      test "returns true when a account screening profile has a screening status of #{status}" do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: status)
        assert personal_profile.temporary_status?
      end
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - TradeControls::SdnScreeningTestHelper::SDN_TEMPORARY_STATUSES).each do |status|
      test "returns false when a account screening profile has a screening status of #{status}" do
        personal_profile = create(:account_screening_profile, msft_trade_screening_status: status)
        refute personal_profile.temporary_status?
      end
    end
  end

  context "PERMANENTLY_BLOCKED_STATUSES" do
    AccountScreeningProfile::PERMANENTLY_BLOCKED_STATUSES.each do |status|
      test "contains #{status}" do
        upp = create(:account_screening_profile, msft_trade_screening_status: status, last_trade_screen_date: 8.days.ago)
        assert upp.permanently_blocked?
      end

      test "user with status #{status} is not permanently blocked if last_trade_screen_date was less than 7 days " do
        upp = create(:account_screening_profile, msft_trade_screening_status: status, last_trade_screen_date: 2.days.ago)
        refute upp.permanently_blocked?
      end
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - AccountScreeningProfile::PERMANENTLY_BLOCKED_STATUSES).each do |status|
      test "does not contain #{status}" do
        upp = create(:account_screening_profile, msft_trade_screening_status: status)
        refute upp.permanently_blocked?
      end
    end
  end

  context "rescreen" do
    AccountScreeningProfile::SDN_STATUS_UPDATE_ALLOW_LIST.each do |status|
      test "rescreens a user when they update PII with screening status #{status} even if they no longer reside in high risk geo" do
        asp = create(:account_screening_profile, msft_trade_screening_status: status, country_code: "IR", last_trade_screen_date: 1.day.ago)
        user = asp.user

        user.enable_feature(:live_sdn_screening)

        asp.update(country_code: "DE")
        assert_in_delta Time.now.utc, asp.last_trade_screen_date, 2.days
        assert_equal "pii_update", asp.metadata["rescreen_reason"]
      end

      test "rescreens an org when they update PII with screening status #{status} even if they no longer reside in high risk geo" do
        owner = create(:user, :verified)
        org = create(:organization, admin: owner)
        org.terms_of_service.update(type: "Corporate", actor: owner)
        asp = create(:account_screening_profile, :with_org, owner: org, msft_trade_screening_status: status, country_code: "IR", last_trade_screen_date: 1.day.ago)

        org.enable_feature(:live_sdn_screening)

        asp.update!(country_code: "DE")
        assert_in_delta Time.now.utc, asp.last_trade_screen_date, 2.days
        assert_equal "pii_update", asp.metadata["rescreen_reason"]
      end

      test "rescreens a business when they update PII with screening status #{status}" do
        asp = create(:account_screening_profile, :with_business, msft_trade_screening_status: status, country_code: "US", last_trade_screen_date: 1.day.ago)
        owner = asp.owner
        owner.enable_feature(:live_sdn_screening)

        asp.update(country_code: "DE")
        assert_in_delta Time.now.utc, asp.last_trade_screen_date, 2.days
        assert_equal "pii_update", asp.metadata["rescreen_reason"]
      end
    end

    test "an lic-r screened record is re-screened for Live SDN when on PII update the record is valid" do
      org = create(:organization, :with_corporate_terms)

      uuid_str = "6c8b6229-3506-427f-aa64-9ce87e9cfa94"
      SecureRandom.stubs(:uuid).returns(uuid_str)
      sdn_response = TradeCompliance::TradeScreening::LiveResponse.parse(response: {
        ScrRespEnv: {
          EId: "5823ebcf-2b26-412b-b2e8-07ad410a2503",
          SummResult: "Hit in Review",
          ScrResps: {
            ScrResp: [
              {
                ReqID: "OrgName_OrgAddr",
                ExternalRefID: uuid_str,
                Result: "Hit in Review",
                ResultDesc: "",
                Type: "Address",
                Errs: {
                  Err: [
                    {
                      ErrCode: "",
                      ErrDesc: ""
                    }
                  ]
                }
              }
            ]
          }
        }
      })
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(sdn_response)

      org.enable_feature(:live_sdn_screening)

      asp = create(:account_screening_profile, :lic_r_enabled_and_no_hit, owner: org)
      org.billing_contact.update(country_code: "DE", address1: "123 Main St", city: "New York", entity_name: "Test Inc.")
      asp.update(country_code: "DE", address1: "123 Main St", city: "New York", entity_name: "Test Inc.")

      assert_equal "pii_update", asp.metadata["rescreen_reason"]
      asp.reload
      assert_predicate asp, :hit_in_review?

      refute Failbot.reports.last
    end
  end

  context "#reset_screening_context" do
    test "does not delete screening_context or send email when new screening status is true_match" do
      profile = create :account_screening_profile, :with_org, msft_trade_screening_status: "lic_a",
        metadata: { screening_context: "test_flow" }

      profile.organization.expects(:send_trade_controls_restricted_free_org_allowed_email).never
      profile.true_match!

      assert profile.reload.metadata["screening_context"]
    end

    test "does not delete screening_context or send email when new screening status is hit_in_review" do
      profile = create :account_screening_profile, :with_org, :lic_r, metadata: { screening_context: "test_flow" }

      profile.organization.expects(:send_trade_controls_restricted_free_org_allowed_email).never
      profile.hit_in_review!

      assert profile.reload.metadata["screening_context"]
    end

    test "deletes screening_context when new screening status is not true_match or hit_in_review for test_flow" do
      profile = create :account_screening_profile, :with_org, :lic_a, metadata: { screening_context: "test_flow" }

      profile.organization.expects(:send_trade_controls_restricted_free_org_allowed_email).never
      profile.lic_r!

      refute profile.reload.metadata["screening_context"]
    end

    test "deletes screening_context and notifies profile owner via email if new status is not hit_in_review or true_match for new_org_creation" do
      profile = create :account_screening_profile, :with_org, :lic_a, metadata: { screening_context: "new_org_creation" }

      profile.organization.expects(:send_trade_controls_restricted_free_org_allowed_email).once
      profile.no_hit!

      refute profile.reload.metadata["screening_context"]
    end

    test "deletes screening_context and does not notify profile owner for new_org_creation that's user owned" do
      profile = create :account_screening_profile, :lic_a, metadata: { screening_context: "new_org_creation" }

      profile.owner.expects(:send_trade_controls_restricted_free_org_allowed_email).never
      profile.no_hit!

      refute profile.reload.metadata["screening_context"]
    end

    test "deletes screening_context and does not notify profile owner for new_org_creation that's business owned" do
      profile = create :account_screening_profile, :with_business, :lic_a, metadata: { screening_context: "new_org_creation" }

      profile.owner.expects(:send_trade_controls_restricted_free_org_allowed_email).never
      profile.no_hit!

      refute profile.reload.metadata["screening_context"]
    end
  end

  context "#update_marketplace_owner_metadata" do
    test "doesn't set the metadata for a Business" do
      profile = create :account_screening_profile, :with_business

      profile.update msft_trade_screening_status: :lic_r

      refute profile.reload.metadata["marketplace_app_owner"]
    end

    test "doesn't set the metadata for a user without a marketplace listing" do
      profile = create :account_screening_profile, :with_org

      profile.update msft_trade_screening_status: :lic_r

      refute profile.reload.metadata["marketplace_app_owner"]
    end

    test "sets the metadata for user with an integration" do
      owner = create(:organization)
      create :integration, :with_marketplace_listing, owner: owner

      profile = create :account_screening_profile, :with_org, owner: owner

      assert profile.reload.metadata["marketplace_app_owner"]
    end

    test "sets the metadata for user with an oauth application" do
      owner = create(:organization)
      oauth_app = create :oauth_application, user: owner
      create :marketplace_listing, listable: oauth_app

      profile = create :account_screening_profile, :with_org, owner: owner

      assert profile.reload.metadata["marketplace_app_owner"]
    end

    test "clears the metadata for users with no marketplace app" do
      profile = create :account_screening_profile, :with_org,
        metadata: { marketplace_app_owner: true }

      profile.update msft_trade_screening_status: :lic_r

      refute profile.reload.metadata["marketplace_app_owner"]
    end
  end

  context ".marketplace_app_owners" do
    test "returns records where metadata tracks the owner as owning a marketplace listing" do
      create :account_screening_profile, :marketplace_app_owner
      create :account_screening_profile

      assert_equal 1, AccountScreeningProfile.marketplace_app_owners.count
    end
  end

  context "#has_delete_trade_restrictions?" do
    TEST_SDN_STATUS_REMOVE_ALLOW_LIST.each do |status|
      test "returns false if the profile has a #{status} screening status" do
        user = create(:credit_card_user, :verified)
        profile = create(:account_screening_profile, msft_trade_screening_status: status, owner: user)

        refute profile.has_delete_trade_restrictions?
      end
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - TEST_SDN_STATUS_REMOVE_ALLOW_LIST).each do |status|
      test "returns true if the profile has a #{status} screening status" do
        user = create(:credit_card_user, :verified)
        profile = create(:account_screening_profile, msft_trade_screening_status: status, owner: user)

        assert profile.has_delete_trade_restrictions?
      end
    end
  end

  context "#rescreen_on_pii_update" do
    test "re-screens a record on PII update if the record has been previously screened" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, msft_trade_screening_status: "no_hit", owner: user, last_trade_screen_date: Time.now.utc - 1.minute)
      user.enable_feature(:live_sdn_screening)

      user.stubs(:perform_live_sdn_screening).once
      profile.update(first_name: "Joker")
    end

    test "does not re-screen if the record schema is invalid" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, msft_trade_screening_status: "no_hit", owner: user, last_trade_screen_date: Time.now.utc - 1.minute)
      user.enable_feature(:live_sdn_screening)

      user.stubs(:perform_live_sdn_screening).never
      profile.first_name = ""
      profile.last_name = ""
      profile.save(validate: false)
    end
  end

  context "#remove_billing_information" do
    TEST_SDN_STATUS_REMOVE_ALLOW_LIST.each do |status|
      test "clears all PII data with the screening status #{status}" do
        user = create(:credit_card_user, :verified)
        profile = create(:account_screening_profile, msft_trade_screening_status: status, owner: user)

        assert profile.remove_billing_information(actor: user)

        PROFILE_PII_FIELDS.each do |field|
          assert_equal profile[field], ""
        end
      end
    end

    test "clears all PII data and drops the billing contact if it exists" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, :no_hit, owner: user)
      assert user.billing_contact.present?

      assert profile.remove_billing_information(actor: user)

      PROFILE_PII_FIELDS.each do |field|
        assert_equal profile[field], ""
      end
      refute_predicate user.reload.customer.billing_contact, :persisted?
    end

    test "clears all PII data and doesn't drop the billing contact if read_billing_information_from_contacts is enabled" do
      GitHub.flipper[:read_billing_information_from_contacts].enable
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, :no_hit, owner: user)
      assert user.billing_contact.present?

      assert profile.remove_billing_information(actor: user)

      PROFILE_PII_FIELDS.each do |field|
        assert_equal profile[field], ""
      end
      assert_predicate user.reload.customer.billing_contact, :persisted?
    end

    (AccountScreeningProfile::VALID_SDN_STATUSES - TEST_SDN_STATUS_REMOVE_ALLOW_LIST).each do |status|
      test "does not clear PII data with screening status #{status}" do
        user = create(:credit_card_user, :verified)
        profile = create(:account_screening_profile, msft_trade_screening_status: status, owner: user)

        assert_no_changes -> { profile.attributes } do
          refute profile.remove_billing_information(actor: user)
        end
      end
    end

    test "clears all PII data when already screened for SDN and status is not blocking" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, msft_trade_screening_status: "no_hit", owner: user, last_trade_screen_date: Time.now.utc - 1.minute)
      user.enable_feature(:live_sdn_screening)

      refute_error_reported do
        assert profile.remove_billing_information(actor: user)
      end

      PROFILE_PII_FIELDS.each do |field|
        assert_equal profile[field], ""
      end
    end

    test "clears all PII data for a trial business" do
      business = create(:business, :with_trade_screening_record, :with_credit_card, trial_expires_at: 30.days.from_now)

      refute_error_reported do
        assert business.trade_screening_record.remove_billing_information(actor: business.owners.first)
      end

      PROFILE_PII_FIELDS.each do |field|
        assert_equal business.trade_screening_record[field], ""
      end
    end

    test "does not clear external ID field" do
      profile = create(:account_screening_profile, :no_hit)
      external_id = profile.external_uuid
      assert external_id.present?

      profile.remove_billing_information(actor: profile.owner)

      assert_equal profile.reload.external_uuid, external_id
    end

    test "clears any existing payment methods" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, :no_hit, owner: user)

      assert_predicate user, :has_valid_payment_method?

      profile.remove_billing_information(actor: user)

      user.reload
      refute_predicate user, :has_valid_payment_method?
    end

    test "unlinks any linked organizations" do
      admin = create(:credit_card_user, :verified, :with_trade_screening_record)
      org = create(:organization, admin: admin)
      org2 = create(:organization, admin: admin)
      org3 = create(:organization, admin: admin)
      admin.link_trade_screening_record_to_org(organization: org)
      assert_predicate org.trade_screening_record, :persisted?
      assert admin.has_trade_screening_record_linked_to_org?(organization: org)
      admin.link_trade_screening_record_to_org(organization: org2)
      assert_predicate org2.trade_screening_record, :persisted?
      assert admin.has_trade_screening_record_linked_to_org?(organization: org2)
      admin.link_trade_screening_record_to_org(organization: org3)
      assert_predicate org3.trade_screening_record, :persisted?
      assert admin.has_trade_screening_record_linked_to_org?(organization: org3)

      # Load up a new user instance to get rid of memoized values for linked orgs
      admin = User.find(admin.id)
      admin.trade_screening_record.remove_billing_information(actor: admin)

      refute_predicate org.reload.trade_screening_record, :persisted?
      refute admin.has_trade_screening_record_linked_to_org?(organization: org)
      refute_predicate org2.reload.trade_screening_record, :persisted?
      refute admin.has_trade_screening_record_linked_to_org?(organization: org2)
      refute_predicate org3.reload.trade_screening_record, :persisted?
      refute admin.has_trade_screening_record_linked_to_org?(organization: org3)
    end

    test "logs that the user has cleared their PII data" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, :no_hit, owner: user)

      expected_log = {
        "Body": "account_screening_profile.remove_billing_information.success",
        "gh.sdn_api_service.owner_type": profile.owner_type,
        "gh.sdn_api_service.status": profile.msft_trade_screening_status,
        "gh.sdn_api_service.external_uuid": profile.external_uuid,
      }

      assert_logged(**expected_log) do
        profile.remove_billing_information(actor: user)
      end
    end

    test "logs that there was an error clearing the PII data" do
      user = create(:credit_card_user, :verified)
      profile = create(:account_screening_profile, :no_hit, owner: user)
      profile.stubs(:save).raises(ActiveRecord::ActiveRecordError.new("test"))

      expected_log = {
        "Body": "account_screening_profile.remove_billing_information.failed",
        "gh.sdn_api_service.owner_type": profile.owner_type,
        "gh.sdn_api_service.status": profile.msft_trade_screening_status,
        "gh.sdn_api_service.external_uuid": profile.external_uuid,
        "error.message": "test",
      }

      assert_logged(**expected_log) do
        profile.remove_billing_information(actor: user)
      end
    end
  end
end
