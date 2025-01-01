# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCreateSponsorsListingTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include HydroTestHelpers

  fixtures do
    @user = create(:verified_user,
      created_at: (SponsorsListing::MANUAL_PAYOUT_NEW_USER_THRESHOLD + 1.hour).ago
    )
    @org_admin = create(:user, :sponsors_old_enough_to_not_get_auto_banned)
    @org = create(:organization, :sponsors_old_enough_to_not_get_auto_banned, admin: @org_admin)

    @user_survey = Sponsors::UserWaitlistSurvey.find_or_create_survey
    @org_survey = Sponsors::OrganizationWaitlistSurvey.find_or_create_survey

    @osc_listing = create(:sponsors_listing, :approved, :open_source_collective)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    setup_staff_user
  end

  test "marks potential sponsorships as having the Sponsors listing created" do
    potential_sponsorship1 = create(:potential_sponsorship, :acknowledged, potential_sponsorable: @user)
    potential_sponsorship2 = create(:potential_sponsorship, potential_sponsorable: @user)

    listing = assert_difference(-> { SponsorsListing.count }) do
      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    refute_nil listing
    assert_predicate potential_sponsorship1.reload, :sponsors_listing_created?
    assert_predicate potential_sponsorship2.reload, :sponsors_listing_created?
  end

  test "does not modify potential sponsorship as sponsors_listing_created when it's for a different potential sponsorable" do
    unrelated_potential_sponsorship = create(:potential_sponsorship) # not for @user

    listing = assert_difference(-> { SponsorsListing.count }) do
      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    refute_nil listing
    assert_predicate unrelated_potential_sponsorship.reload, :pending?
  end

  test "creates a draft sponsors listing for a user who can be auto accepted" do
    @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)
    listing = @user.sponsors_listing
    assert_nil listing
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never
    SponsorsPrimerMailer.expects(:waitlist_acceptance).never

    assert_difference([-> { SponsorsListingStafftoolsMetadata.count }]) do
      listing = Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
        full_description: "Please choose to sponsor *me*",
      )
    end

    refute_nil listing
    assert_predicate listing, :draft?
    refute_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_nil listing.parent_listing
    assert_equal @user, listing.sponsorable
    assert_equal @user_survey, listing.survey
    assert_equal "US", listing.billing_country
    assert_equal "US", listing.country_of_residence
    assert_equal @user.primary_user_email, listing.contact_email
    assert_equal "Support #{@user}'s open source work", listing.short_description
    assert_equal "Support #{@user}'s open source work", listing.featured_description
    assert_equal @user, listing.created_by
    assert_equal "Please choose to sponsor *me*", listing.full_description
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @user.created_at, metadata.sponsorable_created_at
  end

  test "creates a waitlisted sponsors listing for a user who cannot be auto accepted" do
    @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)
    country = "AF"
    refute_nil country, "need a country that won't be auto accepted"
    listing = @user.sponsors_listing
    assert_nil listing
    SponsorsPrimerMailer.expects(:waitlist_confirmation).once.with(
      sponsorable: @user,
      waitlist_title: @user_survey.title,
    ).returns(stub(deliver_later: nil))

    listing = Sponsors::CreateSponsorsListing.with_bank(
      sponsorable: @user,
      billing_country: country,
      country_of_residence: "ES",
      contact_email_id: @user.primary_user_email.id,
      actor: @user,
      survey: @user_survey,
    )

    refute_nil listing
    assert_predicate listing, :waitlisted?
    assert_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_nil listing.parent_listing
    assert_equal @user, listing.sponsorable
    assert_equal @user_survey, listing.survey
    assert_equal country, listing.billing_country
    assert_equal "ES", listing.country_of_residence
    assert_equal @user.primary_user_email, listing.contact_email
    assert_equal "Support #{@user}'s open source work", listing.short_description
    assert_equal "Support #{@user}'s open source work", listing.featured_description
    assert_equal @user, listing.created_by
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @user.created_at, metadata&.sponsorable_created_at
  end

  test "creates a banned sponsors listing for a user who is auto bannable" do
    refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
      "expecting Iran not to be a supported country for this test"
    sponsorable = create(:user, :verified, time_zone_name: "Tehran",
      created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
    )
    listing = sponsorable.sponsors_listing
    assert_nil listing
    SponsorsListing.any_instance.stubs(:public_contribution_count).returns(0)
    ban_reason = SponsorsListing.auto_ban_reason

    perform_enqueued_jobs(only: [BanSponsorsListingJob]) do
      listing = Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: sponsorable,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: sponsorable.primary_user_email.id,
        actor: sponsorable,
        survey: @user_survey,
      )
    end
    stafftools_metadata = listing.stafftools_metadata

    assert_predicate listing.reload, :banned?
    assert_equal ban_reason, stafftools_metadata.reload.banned_reason
    assert_equal User.staff_user, stafftools_metadata.reload.banned_by

    expected_message = {
      user: Hydro::EntitySerializer.user(sponsorable),
      action: "BANNED",
      automated: true,
    }

    assert_hydro_published_partial(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
    assert_hydro_messages(count: 2, schema: "github.sponsors.v0.AccountStatusChange") # create and ban events
  end

  test "sends waitlist confirmation email on creation if not auto acceptable" do
    @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)
    country = "AF"
    refute_nil country, "need a country that won't be auto accepted"
    listing = @user.sponsors_listing
    assert_nil listing
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      listing = Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: country,
        country_of_residence: "ES",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    mail = ActionMailer::Base.deliveries.first
    assert_equal mail.to, [@user.email]
    assert_includes mail.subject, "You're on the GitHub Sponsored Developers waitlist"
    assert_includes mail.html_part.body, "You're on the GitHub Sponsored Developers waitlist!"
    assert_includes mail.text_part.body, "You're on the GitHub Sponsored Developers waitlist!"
  end

  test "creates a draft sponsors listing for a fiscally hosted org who can be auto accepted" do
    listing = @org.sponsors_listing
    assert_nil listing
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never

    listing = Sponsors::CreateSponsorsListing.with_fiscal_host(
      sponsorable: @org,
      billing_country: "",
      country_of_residence: "US",
      contact_email_id: nil,
      actor: @org_admin,
      survey: @org_survey,
      parent_listing_id: @osc_listing.id,
      full_description: "Hello world",
    )

    refute_nil listing
    assert_predicate listing, :draft?
    refute_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_equal @org_survey, listing.survey
    assert_predicate listing, :uses_open_source_collective_as_fiscal_host?
    assert_equal @osc_listing, listing.parent_listing
    assert_equal @org, listing.sponsorable
    assert_equal "Hello world", listing.full_description
    assert_equal @osc_listing.billing_country, listing.billing_country
    assert_equal listing.billing_country, listing.country_of_residence,
      "expected org's country of residence to be set to its billing country"
    assert_nil listing.contact_email
    assert_equal @org.billing_email, listing.contact_email_address
    assert_equal "Support #{@org}'s open source work", listing.short_description
    assert_equal "Support #{@org}'s open source work", listing.featured_description
    assert_equal @org_admin, listing.created_by
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @org.created_at, metadata&.sponsorable_created_at
  end

  test "creates an org listing with a supported fiscal host" do
    listing = @org.sponsors_listing
    assert_nil listing
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never

    listing = Sponsors::CreateSponsorsListing.with_fiscal_host(
      sponsorable: @org,
      parent_listing_id: @osc_listing.id,
      country_of_residence: "US",
      contact_email_id: nil,
      actor: @org_admin,
      survey: @org_survey,
    )

    refute_nil listing
    assert_predicate listing, :draft?
    refute_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_equal @org_survey, listing.survey
    assert_equal @osc_listing, listing.parent_listing
    assert_equal @org, listing.sponsorable
    assert_equal @osc_listing.billing_country, listing.billing_country
    assert_equal listing.billing_country, listing.country_of_residence,
      "expected org's country of residence to be set to its billing country"
    assert_nil listing.contact_email
    assert_equal @org.billing_email, listing.contact_email_address
    assert_equal "Support #{@org}'s open source work", listing.short_description
    assert_equal "Support #{@org}'s open source work", listing.featured_description
    assert_equal @org_admin, listing.created_by
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @org.created_at, metadata&.sponsorable_created_at
  end

  test "creates and accepts a user listing with a supported fiscal host" do
    listing = @org_admin.sponsors_listing
    assert_nil listing
    email = create(:user_email, :verified, user: @org_admin)
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never

    assert_no_enqueued_jobs(only: BanSponsorsListingJob) do
      listing = assert_difference(-> { SponsorsListing.count }) do
        Sponsors::CreateSponsorsListing.with_fiscal_host(
          sponsorable: @org_admin,
          parent_listing_id: @osc_listing.id,
          country_of_residence: "ES",
          contact_email_id: email.id,
          actor: @org_admin,
          survey: @user_survey,
        )
      end
    end

    refute_nil listing
    assert_predicate listing, :draft?
    refute_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_equal @user_survey, listing.survey
    assert_equal @osc_listing, listing.parent_listing
    assert_equal @org_admin, listing.sponsorable
    assert_equal @osc_listing.billing_country, listing.billing_country
    assert_equal "ES", listing.country_of_residence
    assert_equal email, listing.contact_email
    assert_equal "Support #{@org_admin}'s open source work", listing.short_description
    assert_equal "Support #{@org_admin}'s open source work", listing.featured_description
    assert_equal @org_admin, listing.created_by
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @org_admin.created_at, metadata.sponsorable_created_at
  end

  test "errors when the given fiscal_option is invalid" do
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never
    service = Sponsors::CreateSponsorsListing.new(
      sponsorable: @org_admin,
      parent_listing_id: @osc_listing.id,
      country_of_residence: "ES",
      contact_email_id: nil,
      actor: @org_admin,
      survey: @user_survey,
      fiscal_option: "invalid",
    )

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      service.call
    end

    assert_equal "Please provide either the country/region of a bank account or select a fiscal host.", error.message
  end

  test "errors when creating a user listing for someone other than the actor" do
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never
    rando = create(:user)

    error = assert_raises Sponsors::CreateSponsorsListing::ForbiddenError do
      Sponsors::CreateSponsorsListing.with_fiscal_host(
        sponsorable: rando,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    assert_equal "You can only create a GitHub Sponsors profile for yourself or an organization you administer.",
      error.message
  end

  test "errors when creating an org listing for an org the actor does not admin" do
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never
    rando_org = create(:organization)

    error = assert_raises Sponsors::CreateSponsorsListing::ForbiddenError do
      Sponsors::CreateSponsorsListing.with_fiscal_host(
        sponsorable: rando_org,
        parent_listing_id: @osc_listing.id,
        country_of_residence: "US",
        contact_email_id: nil,
        actor: @org_admin,
        survey: @org_survey,
      )
    end

    assert_equal "You can only create a GitHub Sponsors profile for yourself or an organization you administer.",
      error.message
  end

  test "creates an org listing using Open Source Collective with a project profile" do
    listing = @org.sponsors_listing
    assert_nil listing

    listing = Sponsors::CreateSponsorsListing.with_fiscal_host(
      sponsorable: @org,
      billing_country: "",
      parent_listing_id: @osc_listing.id,
      country_of_residence: "US",
      contact_email_id: nil,
      actor: @org_admin,
      survey: @org_survey,
      fiscally_hosted_project_profile_url: "https://fiscal-host.com/some-project"
    )

    refute_nil listing
    assert_equal "https://fiscal-host.com/some-project", listing.fiscally_hosted_project_profile_url
  end


  test "does not set payout probation dates if not exempt from payout probation" do
    join_date = SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never

    listing = travel_to(join_date) do
      @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)

      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    assert_predicate listing, :draft?
    assert_equal join_date, listing.accepted_at
    assert_equal join_date, listing.joined_at
    assert_equal "US", listing.billing_country
    assert_equal @user_survey, listing.survey
    assert_equal "US", listing.country_of_residence
    assert_equal @user.primary_user_email, listing.contact_email
    assert_equal "Support #{@user}'s open source work", listing.short_description
    assert_equal "Support #{@user}'s open source work", listing.featured_description
    assert_equal @user, listing.created_by
    assert_nil listing.payout_probation_started_at
    assert_nil listing.payout_probation_ended_at
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal @user.created_at, metadata.sponsorable_created_at
  end

  test "raises UnprocessableError if specified fiscal host is invalid" do
    non_fiscal_host_listing = create(:sponsors_listing)

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_fiscal_host(
        sponsorable: @org,
        billing_country: "US",
        country_of_residence: "US",
        actor: @org_admin,
        survey: @org_survey,
        contact_email_id: nil,
        parent_listing_id: non_fiscal_host_listing.id,
      )
    end

    assert_equal "The specified fiscal host, #{non_fiscal_host_listing.sponsorable_login}, is not supported.",
      error.message
  end

  test "raises UnprocessableError when the given parent listing ID is for a fiscal host but signup is disallowed using them" do
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never
    invalid_fiscal_host_login = SponsorsListing::FiscalHostDependency::USER_HIDDEN_FISCAL_HOSTS.first
    invalid_parent_listing = create(:sponsors_listing, :fiscal_host, sponsorable_login: invalid_fiscal_host_login)

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_fiscal_host(
        sponsorable: @org_admin,
        parent_listing_id: invalid_parent_listing.id,
        country_of_residence: "ES",
        contact_email_id: nil,
        actor: @org_admin,
        survey: @user_survey,
      )
    end

    assert_equal "The specified fiscal host, #{invalid_fiscal_host_login}, is not supported.", error.message
  end

  test "raises UnprocessableError when the given parent listing ID is not for an existing Sponsors listing" do
    SponsorsPrimerMailer.expects(:waitlist_confirmation).never

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_fiscal_host(
        sponsorable: @org_admin,
        parent_listing_id: (SponsorsListing.order(id: :desc).first&.id || 1) + 1000,
        country_of_residence: "ES",
        contact_email_id: nil,
        actor: @org_admin,
        survey: @user_survey,
      )
    end

    assert_equal "The specified fiscal host is not supported.", error.message
  end

  test "raises UnprocessableError if email is not verified" do
    user = create(:user)
    unverified_email = create(:user_email, user: user)
    refute_predicate unverified_email, :verified?

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: unverified_email.id,
        actor: user,
        survey: @user_survey,
      )
    end

    assert_equal "Contact email must be verified", error.message
  end

  test "raises UnprocessableError if email does not belong to sponsorable" do
    user = create(:user)
    email = create(:verified_user_email)
    assert_predicate email, :verified?
    refute_equal user, email.user

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: email.id,
        actor: user,
        survey: @user_survey,
      )
    end

    assert_equal "Contact email is invalid for sponsorable", error.message
  end

  test "raises UnprocessableError if sponsorable already has a Sponsors listing" do
    create(:sponsors_listing, sponsorable: @user)

    error = assert_raises Sponsors::CreateSponsorsListing::UnprocessableError do
      Sponsors::CreateSponsorsListing.with_bank(
        sponsorable: @user,
        billing_country: "US",
        country_of_residence: "US",
        contact_email_id: @user.primary_user_email.id,
        actor: @user,
        survey: @user_survey,
      )
    end

    assert_equal "#{@user} already has a GitHub Sponsors profile", error.message
  end

  test "does not auto-accept listing from spammer" do
    spammer = create(:spammy_user, :verified, :sponsors_old_enough_to_not_get_auto_banned)
    listing = spammer.sponsors_listing
    assert_nil listing
    SponsorsPrimerMailer.expects(:waitlist_confirmation).once.with(
      sponsorable: spammer,
      waitlist_title: @user_survey.title,
    ).returns(stub(deliver_later: nil))

    listing = Sponsors::CreateSponsorsListing.with_bank(
      sponsorable: spammer,
      billing_country: "US",
      country_of_residence: "US",
      contact_email_id: spammer.primary_user_email.id,
      actor: spammer,
      survey: @user_survey,
    )

    refute_nil listing
    assert_predicate listing, :waitlisted?
    assert_nil listing.accepted_at
    refute_nil listing.joined_at
    assert_nil listing.parent_listing
    assert_equal spammer, listing.sponsorable
    assert_equal @user_survey, listing.survey
    assert_equal "US", listing.billing_country
    assert_equal "US", listing.country_of_residence
    assert_equal spammer.primary_user_email, listing.contact_email
    assert_equal "Support #{spammer}'s open source work", listing.short_description
    assert_equal "Support #{spammer}'s open source work", listing.featured_description
    assert_equal spammer, listing.created_by
    metadata = listing.stafftools_metadata
    refute_nil metadata
    assert_equal spammer.created_at, metadata&.sponsorable_created_at
  end if GitHub.spamminess_check_enabled?

  test "creates a draft sponsors listing with default full description" do
    @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)
    listing = @user.sponsors_listing
    assert_nil listing

    listing = Sponsors::CreateSponsorsListing.with_bank(
      sponsorable: @user,
      billing_country: "US",
      country_of_residence: "US",
      contact_email_id: @user.primary_user_email.id,
      actor: @user,
      survey: @user_survey,
    )

    refute_nil listing
    assert_predicate listing, :draft?
    assert_equal "Support #{@user}'s open source work", listing.full_description
  end

  test "creates a draft sponsors listing with given full description" do
    @user.update!(created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago)
    listing = @user.sponsors_listing
    assert_nil listing

    listing = Sponsors::CreateSponsorsListing.with_bank(
      sponsorable: @user,
      billing_country: "US",
      country_of_residence: "US",
      contact_email_id: @user.primary_user_email.id,
      actor: @user,
      survey: @user_survey,
      full_description: "Please support me :)"
    )

    refute_nil listing
    assert_predicate listing, :draft?
    assert_equal "Please support me :)", listing.full_description
  end
end
