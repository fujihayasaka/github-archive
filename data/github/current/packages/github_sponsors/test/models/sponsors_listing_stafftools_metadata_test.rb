# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingStafftoolsMetadataTest < GitHub::TestCase
  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "validations" do
    test "requires a Sponsors listing" do
      metadata = SponsorsListingStafftoolsMetadata.new
      refute_predicate metadata, :valid?
      assert_includes metadata.errors[:sponsors_listing], "must exist"
    end

    test "requires a sponsorable" do
      metadata = SponsorsListingStafftoolsMetadata.new
      refute_predicate metadata, :valid?
      assert_includes metadata.errors[:sponsorable], "must exist"
    end

    test "requires a unique Sponsors listing" do
      metadata1 = create(:sponsors_listing_stafftools_metadata)
      metadata2 = build(:sponsors_listing_stafftools_metadata, sponsors_listing: metadata1.sponsors_listing)
      refute_predicate metadata2, :valid?
      assert_includes metadata2.errors[:sponsors_listing_id], "has already been taken"
    end

    test "requires a unique sponsorable" do
      metadata1 = create(:sponsors_listing_stafftools_metadata)
      metadata2 = SponsorsListingStafftoolsMetadata.new(sponsorable_id: metadata1.sponsorable_id)
      refute_predicate metadata2, :valid?
      assert_includes metadata2.errors[:sponsorable_id], "has already been taken"
    end

    test "requires sponsorable creation time" do
      metadata = SponsorsListingStafftoolsMetadata.new
      refute_predicate metadata, :valid?
      assert_includes metadata.errors[:sponsorable_created_at], "can't be blank"
    end

    test "requires sponsorable creation time match the sponsorable of the specified listing" do
      sponsorable = travel_to(1.year.ago) { create(:user, :sponsorable) }
      listing = sponsorable.sponsors_listing
      metadata = listing.stafftools_metadata
      metadata.sponsorable_created_at = Time.now
      refute_predicate metadata, :valid?
      assert_includes metadata.errors[:sponsorable_created_at], "doesn't match the sponsorable's creation time " \
        "for #{sponsorable}"
    end
  end

  test "sets sponsorable details on create" do
    sponsorable = create(:user, :verified, time_zone_name: "America/Los_Angeles")
    create(:profile, user: sponsorable, bio: "I love the fishes 'cause they're so delicious")
    create(:abuse_report, :user_report, reported_user: sponsorable)
    create(:repository, owner: sponsorable)
    listing = create(:sponsors_listing, sponsorable: sponsorable, should_create_stafftools_metadata: false)
    metadata = SponsorsListingStafftoolsMetadata.new(sponsors_listing: listing)

    assert metadata.save

    assert_equal sponsorable, metadata.sponsorable
    assert_equal sponsorable.created_at, metadata.sponsorable_created_at
    assert_equal "America/Los_Angeles", metadata.sponsorable_time_zone_name
    assert_predicate metadata, :has_received_abuse_report?
    assert_predicate metadata, :has_customized_user_profile?
    assert_predicate metadata, :has_public_non_fork_repository?
  end

  context ".profile_changes_can_affect_has_customized_user_profile?" do
    test "returns true when any relevant profile field gets a non-blank value" do
      changes = { "bio" => [nil, "Hello world"] }
      assert SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end

    test "returns true when all the relevant fields get wiped out" do
      changes = { "bio" => ["Hello world", nil] }
      assert SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end

    test "returns false when relevant field gets a changed value that wasn't originally blank" do
      changes = { "bio" => ["old value", "new value"] }
      refute SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end

    test "returns false when the only relevant field change is from nil to a blank string" do
      changes = { "bio" => [nil, ""] }
      refute SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end

    test "returns false when the only relevant field change is from a blank string to nil" do
      changes = { "bio" => ["", nil] }
      refute SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end

    test "returns false when no relevant fields are changed" do
      refute_includes SponsorsListingStafftoolsMetadata::PROFILE_CUSTOMIZATION_FIELDS, :updated_at,
        "need a field that isn't one we care about for profile changes"
      changes = { "updated_at" => [nil, Time.now] }
      refute SponsorsListingStafftoolsMetadata.profile_changes_can_affect_has_customized_user_profile?(changes)
    end
  end

  context ".profile_customized_for_sponsors?" do
    test "returns true when sponsorable has a profile name" do
      profile = Profile.new(name: "foo")
      assert SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end

    test "returns true when sponsorable has a profile bio" do
      profile = Profile.new(bio: "foo")
      assert SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end

    test "returns true when sponsorable has a profile website URL" do
      profile = Profile.new(blog: "foo")
      assert SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end

    test "returns true when sponsorable has a profile company" do
      profile = Profile.new(company: "foo")
      assert SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end

    test "returns true when sponsorable has a profile Twitter username" do
      profile = Profile.new(twitter_username: "foo")
      assert SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end

    test "returns false when sponsorable has no profile" do
      refute SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(nil)
    end

    test "returns false when sponsorable has a profile but lacks customization in fields we care about" do
      profile = Profile.new(email: "someemail@example.com", name: " ", bio: "",
        twitter_username: nil, blog: nil, company: nil)
      refute SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    end
  end

  context "without_time_zone scope" do
    test "filters based on sponsorable_time_zone_name" do
      nil_time_zone = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: nil)
      blank_time_zone = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: "")
      has_time_zone = create(:sponsors_listing_stafftools_metadata, :with_time_zone)

      result = SponsorsListingStafftoolsMetadata.without_time_zone.pluck(:id)

      assert_includes result, nil_time_zone.id
      assert_includes result, blank_time_zone.id
      refute_includes result, has_time_zone.id
    end
  end

  context "with_time_zone scope" do
    test "includes metadata where the sponsorable has a time zone" do
      supported_tz = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone)
      unsupported_tz = create(:sponsors_listing_stafftools_metadata, :with_unsupported_time_zone)
      no_time_zone = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: nil)

      result = SponsorsListingStafftoolsMetadata.with_time_zone.pluck(:id)

      assert_includes result, unsupported_tz.id
      assert_includes result, supported_tz.id
      refute_includes result, no_time_zone.id
    end
  end

  context "unsupported_time_zone scope" do
    test "filters based on sponsorable_time_zone_name" do
      supported_tz = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone)
      unsupported_tz = create(:sponsors_listing_stafftools_metadata, :with_unsupported_time_zone)
      no_time_zone = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: nil)

      result = SponsorsListingStafftoolsMetadata.unsupported_time_zone.pluck(:id)

      assert_includes result, unsupported_tz.id
      refute_includes result, supported_tz.id
      refute_includes result, no_time_zone.id, "should not include listing whose sponsorable has no time zone"
    end
  end

  context "with_time_zone_matching_country scope" do
    test "includes metadata where the sponsorable's time zone is one within the specified country" do
      country_code = "US"
      metadata1 = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone,
        time_zone_name: "America/New_York")
      metadata2 = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone,
        time_zone_name: "America/Vancouver")
      metadata3 = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone,
        time_zone_name: "America/Los_Angeles")

      result = SponsorsListingStafftoolsMetadata.with_time_zone_matching_country(country_code).pluck(:id)

      assert_includes result, metadata1.id
      refute_includes result, metadata2.id, "should not include Canadian time zone"
      assert_includes result, metadata3.id
    end

    test "includes metadata where the sponsorable has no time zone when no country code is given" do
      metadata1 = create(:sponsors_listing_stafftools_metadata, :with_supported_time_zone)
      metadata2 = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: nil)
      metadata3 = create(:sponsors_listing_stafftools_metadata, sponsorable_time_zone_name: "")

      result = SponsorsListingStafftoolsMetadata.with_time_zone_matching_country(nil).pluck(:id)
      refute_includes result, metadata1.id, "should not include metadata that has a non-blank sponsorable time zone"
      assert_includes result, metadata2.id
      assert_includes result, metadata3.id

      result = SponsorsListingStafftoolsMetadata.with_time_zone_matching_country("").pluck(:id)
      refute_includes result, metadata1.id, "should not include metadata that has a non-blank sponsorable time zone"
      assert_includes result, metadata2.id
      assert_includes result, metadata3.id
    end
  end

  context "without_public_non_fork_repository scope" do
    test "filters based on has_public_non_fork_repository" do
      no_public_non_fork_repos = create(:sponsors_listing_stafftools_metadata, has_public_non_fork_repository: false)
      has_public_non_fork_repo = create(:sponsors_listing_stafftools_metadata, :with_public_non_fork_repository)

      result = SponsorsListingStafftoolsMetadata.without_public_non_fork_repository.pluck(:id)

      assert_includes result, no_public_non_fork_repos.id
      refute_includes result, has_public_non_fork_repo.id
    end
  end

  context "uncustomized_github_profile scope" do
    test "filters based on has_customized_user_profile" do
      has_customized = create(:sponsors_listing_stafftools_metadata, :has_customized_user_profile)
      has_not_customized = create(:sponsors_listing_stafftools_metadata, has_customized_user_profile: false)

      result = SponsorsListingStafftoolsMetadata.uncustomized_github_profile
        .where(id: [has_customized, has_not_customized]).pluck(:id)

      assert_includes result, has_not_customized.id,
        "expected it to include the metadata where the user hasn't customized their profile"
      refute_includes result, has_customized.id
    end
  end

  context "ordered_by_user_creation_time scope" do
    test "sorts with newest GitHub users first" do
      old_user_metadata = travel_to(4.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      middle_user_metadata = travel_to(2.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      new_user_metadata = create(:sponsors_listing_stafftools_metadata)
      all_metadata = [old_user_metadata, middle_user_metadata, new_user_metadata]

      result = SponsorsListingStafftoolsMetadata.where(id: all_metadata).ordered_by_user_creation_time(:desc)

      assert_equal [new_user_metadata, middle_user_metadata, old_user_metadata], result
    end

    test "sorts with oldest GitHub users first" do
      old_user_metadata = travel_to(4.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      middle_user_metadata = travel_to(2.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      new_user_metadata = create(:sponsors_listing_stafftools_metadata)
      all_metadata = [old_user_metadata, middle_user_metadata, new_user_metadata]

      result = SponsorsListingStafftoolsMetadata.where(id: all_metadata).ordered_by_user_creation_time(:asc)

      assert_equal [old_user_metadata, middle_user_metadata, new_user_metadata], result
    end

    test "defaults to descending order when invalid direction is given" do
      old_user_metadata = travel_to(4.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      middle_user_metadata = travel_to(2.years.ago) { create(:sponsors_listing_stafftools_metadata) }
      new_user_metadata = create(:sponsors_listing_stafftools_metadata)
      all_metadata = [old_user_metadata, middle_user_metadata, new_user_metadata]

      result = SponsorsListingStafftoolsMetadata.where(id: all_metadata).ordered_by_user_creation_time(:bad_direction)

      assert_equal [new_user_metadata, middle_user_metadata, old_user_metadata], result
    end
  end

  context "sponsorable_profile relation" do
    test "returns the profile associated with the sponsorable" do
      metadata = create(:sponsors_listing_stafftools_metadata)
      sponsorable = metadata.sponsorable
      assert_nil metadata.sponsorable_profile

      profile = create(:profile, user: sponsorable)
      assert_equal profile, metadata.reload_sponsorable_profile
    end
  end

  context "sponsorable_received_abuse_reports relation" do
    test "returns abuse reports the sponsorable is the recipient of" do
      metadata = create(:sponsors_listing_stafftools_metadata)
      sponsorable = metadata.sponsorable
      assert_empty metadata.sponsorable_received_abuse_reports

      abuse_report = create(:abuse_report, :user_report, reported_user: sponsorable)
      assert_equal [abuse_report], metadata.sponsorable_received_abuse_reports
    end
  end

  context "sponsorable_non_fork_public_repositories relation" do
    test "returns public non-fork repositories owned by the sponsorable" do
      metadata = create(:sponsors_listing_stafftools_metadata)
      sponsorable = metadata.sponsorable
      assert_empty metadata.sponsorable_non_fork_public_repositories

      # Create some repos to see which ones get included in the relation:
      public_repository = create(:repository, owner: sponsorable)

      create(:private_repository, owner: sponsorable)

      someone_elses_repo = create(:repository)

      forked_repo = create(:fork_repository, forker: sponsorable, fork_repo: someone_elses_repo)
      assert_equal_owner sponsorable, forked_repo.owner

      create(:repository, :soft_deleted, owner: sponsorable)

      assert_equal [public_repository], metadata.sponsorable_non_fork_public_repositories
    end
  end

  context "#reviewed?" do
    test "returns true when reviewed_at is set" do
      assert_predicate SponsorsListingStafftoolsMetadata.new(reviewed_at: Time.now), :reviewed?
    end

    test "returns false when reviewed_at is nil" do
      refute_predicate SponsorsListingStafftoolsMetadata.new(reviewed_at: nil), :reviewed?
    end
  end

  context "#in_current_state_since" do
    test "returns reviewed_at when given disabled state" do
      reviewed_at = Time.now
      metadata = SponsorsListingStafftoolsMetadata.new(reviewed_at: reviewed_at)
      assert_equal reviewed_at.to_i, metadata.in_current_state_since(:disabled).to_i
    end

    test "returns nil when approval_requested_at is not set and given pending_approval state" do
      metadata = SponsorsListingStafftoolsMetadata.new(approval_requested_at: nil)
      assert_nil metadata.in_current_state_since(:pending_approval)
    end

    test "returns approval_requested_at when given pending_approval state" do
      approval_requested_at = Time.now
      metadata = SponsorsListingStafftoolsMetadata.new(approval_requested_at: approval_requested_at)
      assert_equal approval_requested_at.to_i, metadata.in_current_state_since(:pending_approval).to_i
    end

    test "returns banned_at when given banned state" do
      banned_at = Time.now
      metadata = SponsorsListingStafftoolsMetadata.new(banned_at: banned_at)
      assert_equal banned_at.to_i, metadata.in_current_state_since(:banned).to_i
    end

    test "returns reviewed_at when given spammy state" do
      reviewed_at = Time.now
      metadata = SponsorsListingStafftoolsMetadata.new(reviewed_at: reviewed_at)
      assert_equal reviewed_at.to_i, metadata.in_current_state_since(:spammy).to_i
    end
  end

  context "#recently_created_github_account?" do
    test "returns true when sponsorable signed up within the last 60 days" do
      metadata = SponsorsListingStafftoolsMetadata.new(sponsorable_created_at: 1.day.ago)
      assert_predicate metadata, :recently_created_github_account?
    end

    test "returns false when sponsorable signed up more than 60 days ago" do
      metadata = SponsorsListingStafftoolsMetadata.new(sponsorable_created_at: 61.days.ago)
      refute_predicate metadata, :recently_created_github_account?
    end
  end
end
