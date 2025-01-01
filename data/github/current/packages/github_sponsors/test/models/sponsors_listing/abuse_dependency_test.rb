# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingAbuseDependencyTest < GitHub::TestCase
  fixtures do
    @listing = create(:sponsors_listing)
    @sponsorable = @listing.sponsorable
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#sponsorable_has_public_non_fork_repository?" do
    test "returns true when sponsorable has a public repository that isn't a fork" do
      create(:repository, :full_creation, owner: @sponsorable)
      assert_predicate @listing, :sponsorable_has_public_non_fork_repository?
    end

    test "returns true when sponsorable has public forks and non-forks" do
      source_repo = create(:repository, :full_creation)
      forked_repo = create(:fork_repository, forker: @sponsorable, fork_repo: source_repo)
      refute_nil forked_repo

      create(:repository, :full_creation, owner: @sponsorable)

      assert_predicate @listing, :sponsorable_has_public_non_fork_repository?
    end

    test "returns false when sponsorable has no repositories" do
      refute_predicate @listing, :sponsorable_has_public_non_fork_repository?
    end

    test "returns false when sponsorable has only private repositories" do
      create(:private_repository, owner: @sponsorable)
      refute_predicate @listing, :sponsorable_has_public_non_fork_repository?
    end

    test "returns false when sponsorable only has a public forked repo" do
      source_repo = create(:repository)
      forked_repo = create(:fork_repository, forker: @sponsorable, fork_repo: source_repo)
      refute_nil forked_repo
      refute_predicate @listing, :sponsorable_has_public_non_fork_repository?
    end
  end

  context "#supported_country_of_residence?" do
    test "returns true when the listing has a supported country of residence" do
      country_code = Billing::StripeConnect::Account.supported_countries.first
      assert_predicate SponsorsListing.new(country_of_residence: country_code), :supported_country_of_residence?
    end

    test "returns false when the listing has an unsupported country of residence" do
      country_code = Billing::StripeConnect::Account.unsupported_countries.first
      refute_predicate SponsorsListing.new(country_of_residence: country_code), :supported_country_of_residence?
    end
  end

  context "#sponsorable_timezone_matches_country_of_residence?" do
    test "returns true when timezone exists within the sponsorable's country of residence" do
      user = create(:user, :verified, time_zone_name: "America/Chicago")
      listing = create(:sponsors_listing, sponsorable: user, country_of_residence: "US")
      assert_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end

    test "returns false when timezone does not exist within the sponsorable's country of residence" do
      user = create(:user, :verified, time_zone_name: "Europe/Budapest")
      listing = create(:sponsors_listing, sponsorable: user, country_of_residence: "US")
      refute_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end

    test "returns false when sponsorable has no time zone but did specify a country of residence" do
      user = create(:user, :verified, time_zone_name: nil)
      listing = create(:sponsors_listing, sponsorable: user, country_of_residence: "US")
      refute_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end

    test "returns false when sponsorable has no country of residence but does have a time zone" do
      user = create(:user, :verified, time_zone_name: "Edinburgh")
      listing = create(:sponsors_listing, sponsorable: user)
      listing.update_attribute(:country_of_residence, nil)
      refute_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end

    test "returns true when sponsorable does not have a time zone or country of residence" do
      user = create(:user, :verified, time_zone_name: nil)
      listing = create(:sponsors_listing, sponsorable: user)
      listing.update_attribute(:country_of_residence, nil)
      assert_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end

    # See https://github.com/github/sponsors/issues/3747
    test "returns true for IN (India) matching Asia/Calcutta time zone" do
      user = create(:user, :verified, time_zone_name: nil)
      listing = create(:sponsors_listing, sponsorable: user)
      listing.update_attribute(:country_of_residence, nil)
      assert_predicate listing, :sponsorable_timezone_matches_country_of_residence?
    end
  end

  context "#recently_created_github_account?" do
    test "returns true for listing whose sponsorable signed up within the last 60 days" do
      user = travel_to(1.day.ago) { create(:user, :verified) }
      listing = create(:sponsors_listing, sponsorable: user)
      assert_predicate listing, :recently_created_github_account?
    end

    test "returns false for listing whose sponsorable signed up more than 60 days ago" do
      user = travel_to(61.days.ago) { create(:user, :verified) }
      listing = create(:sponsors_listing, sponsorable: user)
      refute_predicate listing, :recently_created_github_account?
    end
  end

  context "#sponsorable_github_account_old_enough_for_auto_approval?" do
    test "returns true when account is older than 6 months" do
      user = travel_to(6.months.ago) { create(:user, :verified) }
      listing = create(:sponsors_listing, sponsorable: user)
      assert_predicate listing, :sponsorable_github_account_old_enough_for_auto_approval?
    end

    test "returns false when account is younger than 6 months" do
      user = travel_to(5.months.ago) { create(:user, :verified) }
      listing = create(:sponsors_listing, sponsorable: user)
      refute_predicate listing, :sponsorable_github_account_old_enough_for_auto_approval?
    end
  end

  context "#sponsorable_young_enough_for_auto_ban?" do
    test "returns true when account is older than auto-ban age cutoff" do
      user = create(:user, :verified, created_at: 7.months.ago)
      listing = create(:sponsors_listing, sponsorable: user)
      refute_predicate listing, :sponsorable_young_enough_for_auto_ban?
    end

    test "returns false when account is younger than auto-ban age cutoff" do
      user = create(:user, :verified)
      listing = create(:sponsors_listing, sponsorable: user)
      assert_predicate listing, :sponsorable_young_enough_for_auto_ban?
    end
  end

  context "#sponsorable_has_supported_timezone?" do
    test "returns true when listing's sponsorable has a time zone for a supported country" do
      assert_includes Billing::StripeConnect::Account.supported_countries, "AU",
        "expecting Australia to be a supported country for this test"
      sponsorable = create(:user, :sponsorable, time_zone_name: "Canberra")
      assert_predicate sponsorable.sponsors_listing, :sponsorable_has_supported_timezone?
    end

    test "returns false when listing's sponsorable has no time zone" do
      sponsorable = create(:user, :sponsorable, time_zone_name: nil)
      refute_predicate sponsorable.sponsors_listing, :sponsorable_has_supported_timezone?
    end

    test "returns false when listing's sponsorable has a time zone that's only present in an unsupported country" do
      refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
        "expecting Iran not to be a supported country for this test"
      sponsorable = create(:user, :sponsorable, time_zone_name: "Tehran")
      refute_predicate sponsorable.sponsors_listing, :sponsorable_has_supported_timezone?
    end

    # See https://github.com/github/sponsors/issues/3747
    test "returns true when India is supported and deprecated Asia/Calcutta is the reported time zone name" do
      assert_includes Billing::StripeConnect::Account.supported_countries, "IN",
        "expecting India to be a supported country for this test"
      sponsorable = create(:user, :sponsorable, time_zone_name: "Asia/Calcutta")
      assert_predicate sponsorable.sponsors_listing, :sponsorable_has_supported_timezone?
    end
  end

  context "#sponsorable_has_customized_user_profile?" do
    test "returns true when sponsorable has a profile with any fields we care about" do
      create(:profile, user: @sponsorable, name: "foo")
      assert_predicate @listing, :sponsorable_has_customized_user_profile?
    end

    test "returns false when sponsorable has no profile" do
      refute_predicate @listing, :sponsorable_has_customized_user_profile?
    end

    test "returns false when sponsorable has a profile but lacks customization in fields we care about" do
      create(:profile, user: @sponsorable, email: "someemail@example.com", name: " ", bio: "", twitter_username: nil,
        blog: nil, company: nil)
      refute_predicate @listing, :sponsorable_has_customized_user_profile?
    end
  end
end
