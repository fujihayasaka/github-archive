# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BulkSponsorshipValidatorTest < GitHub::TestCase
  context "#errors" do
    test "includes human-readable error messages" do
      expected_errors = [
        "Could not create sponsorships: Actor must be specified, cannot sponsor anonymously",
        "Could not create sponsorships: Sponsor must be specified",
        "Could not create sponsorships: Sponsorship amounts and maintainers must be specified",
      ]
      unless GitHub.sponsors_enabled?
        expected_errors << "Could not create sponsorships: GitHub Sponsors is not available"
      end
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: nil,
        sponsor: nil,
        amounts_by_sponsorable_login: {},
      )

      assert_same_elements expected_errors, validator.errors
    end

    test "errors if end date is specified and sponsor is not an organization" do
      sponsor = create(:credit_card_user, :verified)
      plan_subscription = create(:billing_plan_subscription, purpose: :sponsors,
        user: sponsor,
        customer: sponsor.customer,
      )
      end_date = Date.new(2025, 3, 1)

      expected_errors = ["You cannot set an end date for these sponsorships."]
      unless GitHub.sponsors_enabled?
        expected_errors << "Could not create sponsorships: GitHub Sponsors is not available"
      end

      travel_to("2024-02-12") do
        validator = Sponsors::BulkSponsorshipValidator.new(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { "someUser" => 5 },
          end_date: end_date,
        )
        assert_same_elements expected_errors, validator.errors
      end
    end

    test "errors if end date is specified and org sponsor is not invoiced" do
      admin = create(:verified_user)
      sponsor = create(:credit_card_org, admin: admin)
      plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
      end_date = Date.new(2025, 3, 1)

      expected_errors = ["You cannot set an end date for these sponsorships."]
      unless GitHub.sponsors_enabled?
        expected_errors << "Could not create sponsorships: GitHub Sponsors is not available"
      end

      travel_to("2024-02-12") do
        validator = Sponsors::BulkSponsorshipValidator.new(
          sponsor: sponsor,
          actor: admin,
          amounts_by_sponsorable_login: { "someUser" => 5 },
          end_date: end_date,
        )
        assert_same_elements expected_errors, validator.errors
      end
    end

    test "errors if end date is in the past for an invoiced organization" do
      admin = create(:verified_user)
      sponsor = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
        admin: admin)
      plan_sub = sponsor.sponsors_plan_subscription
      end_date = Date.new(2024, 1, 1)

      expected_errors = ["Please choose an end date in the future."]

      travel_to("2024-02-12") do
        validator = Sponsors::BulkSponsorshipValidator.new(
          sponsor: sponsor,
          actor: admin,
          amounts_by_sponsorable_login: { "someUser" => 5 },
          end_date: end_date,
        )
        assert_same_elements expected_errors, validator.errors
      end
    end if GitHub.sponsors_enabled?

    test "returns an error result when there are more sponsorships than allowed" do
      sponsor = create(:credit_card_user, :verified)
      amounts_by_sponsorable_login = {}
      (Sponsors::BulkSponsorshipValidator::MAX_SPONSORABLES + 1).times do |i|
        amounts_by_sponsorable_login["maintainer#{i}"] = 5
      end

      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: sponsor,
        sponsor: sponsor,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login,
      )

      assert_equal ["You can only sponsor up to #{Sponsors::BulkSponsorshipValidator::MAX_SPONSORABLES} " \
        "maintainers at a time."], validator.errors
    end if GitHub.sponsors_enabled?

    test "flags spammy user sponsor" do
      spammer = create(:spammy_user, :verified, billing_type: "card",
        customer_account_factory: :credit_card_customer_account)
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: spammer,
        sponsor: spammer,
        amounts_by_sponsorable_login: { "someUser" => 5 },
      )
      assert_equal ["Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed."], validator.errors
    end if GitHub.spamminess_check_enabled?

    test "flags spammy org sponsor" do
      non_spammy_org_admin = create(:user, :verified)
      spammy_org = create(:credit_card_organization, :spammy, admin: non_spammy_org_admin)
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: non_spammy_org_admin,
        sponsor: spammy_org,
        amounts_by_sponsorable_login: { "someUser" => 5 },
      )
      assert_equal ["#{spammy_org}'s account is flagged and unable to make purchases. Please contact support to " \
        "have your account reviewed."], validator.errors
    end if GitHub.spamminess_check_enabled?
  end

  context "#valid?" do
    test "returns false when there are validation errors" do
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: nil,
        sponsor: nil,
        amounts_by_sponsorable_login: {},
      )
      refute_empty validator.errors
      refute_predicate validator, :valid?
    end

    test "returns true when there are no validation errors" do
      user = create(:credit_card_user, :verified)
      sponsorable = create(:user, :sponsorable)
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: user,
        sponsor: user,
        amounts_by_sponsorable_login: { sponsorable.login => "1" },
      )
      assert_empty validator.errors
      assert_predicate validator, :valid?
    end if GitHub.sponsors_enabled?

    test "idempotent, doesn't modify errors list with repeated calls" do
      validator = Sponsors::BulkSponsorshipValidator.new(
        actor: nil,
        sponsor: nil,
        amounts_by_sponsorable_login: {},
      )

      refute_predicate validator, :valid?

      original_errors = validator.errors
      refute_empty original_errors

      refute_predicate validator, :valid?
      assert_equal original_errors, validator.errors
    end
  end
end
