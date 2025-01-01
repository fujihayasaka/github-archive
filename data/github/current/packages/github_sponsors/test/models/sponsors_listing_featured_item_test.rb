# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingFeaturedItemTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, :sponsorable)
    @listing = @org.sponsors_listing
  end

  context "ordered_by_position scope" do
    test "sorts featured items by position ascending" do
      item1 = create(:sponsors_listing_featured_item, position: 1)
      item3 = create(:sponsors_listing_featured_item, position: 3, sponsors_listing: item1.sponsors_listing)
      item2 = create(:sponsors_listing_featured_item, position: 2, sponsors_listing: item1.sponsors_listing)

      result = SponsorsListingFeaturedItem.where(id: [item1, item2, item3]).ordered_by_position

      assert_equal [item1, item2, item3], result
    end
  end

  context "#async_description" do
    test "returns description on featured item if present" do
      item = build(:sponsors_listing_featured_item, description: "Hello world")
      assert_equal "Hello world", item.async_description.sync
    end

    test "returns user bio when featureable is a user and featured item description is not present" do
      user = create(:profile, bio: "This is nice").user
      @org.add_member(user)
      item = create(:sponsors_listing_featured_item, description: nil, featureable: user,
        sponsors_listing: @org.sponsors_listing)
      assert_equal "This is nice", item.async_description.sync
    end

    test "returns nil when featureable is a user and featured item description and user bio are not present" do
      user = create(:user)
      @org.add_member(user)
      item = create(:sponsors_listing_featured_item, description: nil, featureable: user,
        sponsors_listing: @org.sponsors_listing)
      assert_nil item.async_description.sync
    end

    test "returns repo description when featureable is a repo and featured item description is not present" do
      repo = create(:repository, owner: @org, description: "such a neat project")
      item = create(:sponsors_listing_featured_item, description: nil, featureable: repo,
        sponsors_listing: @org.sponsors_listing)
      assert_equal "such a neat project", item.async_description.sync
    end
  end

  context "#async_featureable" do
    test "returns nil when repository has been made private" do
      item = create(:sponsors_listing_featured_item)
      item.featureable.update_attribute(:public, false)
      assert_nil item.async_featureable.sync
    end

    test "returns featured repository" do
      repo = create(:repository, owner: @org)
      item = create(:sponsors_listing_featured_item, featureable: repo, sponsors_listing: @org.sponsors_listing)
      assert_equal repo, item.async_featureable.sync
    end

    test "returns featured user" do
      user = create(:user)
      @org.add_member(user)
      item = create(:sponsors_listing_featured_item, featureable: user, sponsors_listing: @org.sponsors_listing)
      assert_equal user, item.async_featureable.sync
    end
  end

  test "destroys the featured items when the listing is destroyed" do
    repo = create(:repository, owner: @org)

    user_item = @listing.featured_items.create(featureable: @org.admin)
    repo_item = @listing.featured_items.create(featureable: repo)

    assert_equal [user_item, repo_item], @listing.featured_items.reload
    assert_difference -> { SponsorsListingFeaturedItem.count }, -2 do
      @listing.destroy
    end

    assert_raises ActiveRecord::RecordNotFound do
      user_item.reload
    end

    assert_raises ActiveRecord::RecordNotFound do
      repo_item.reload
    end
  end

  test "destroys the featured item when featureable is destroyed" do
    repo = create(:repository, owner: @org)
    member = create(:user)
    @org.add_member(member)

    user_item = @listing.featured_items.create(featureable: member)
    repo_item = @listing.featured_items.create(featureable: repo)

    assert_equal [user_item, repo_item], @listing.featured_items.reload
    assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
      member.destroy
    end

    assert_raises ActiveRecord::RecordNotFound do
      user_item.reload
    end

    assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
      repo.destroy
    end

    assert_raises ActiveRecord::RecordNotFound do
      repo_item.reload
    end
  end

  test "destroys featured repos when the repo is destroyed" do
    maintainer = create(:user, :sponsorable)
    maintainer_listing = maintainer.sponsors_listing

    repo = create(:repository, owner: @org)
    create(:commit_contribution, :with_summaries, repository: repo, user: maintainer)

    repo_item = @listing.featured_items.create(featureable: repo)
    maintainer_repo_item = maintainer_listing.featured_items.create(featureable: repo)

    assert_predicate repo_item, :valid?
    assert_predicate maintainer_repo_item, :valid?

    assert_difference -> { SponsorsListingFeaturedItem.count }, -2 do
      repo.destroy
    end

    assert_raises ActiveRecord::RecordNotFound do
      repo_item.reload
    end

    assert_raises ActiveRecord::RecordNotFound do
      maintainer_repo_item.reload
    end
  end

  test "destroys the featured item when is user and gets removed from org" do
    member = create(:user)
    @org.add_member(member)
    item = @listing.featured_items.create(featureable: member)

    other_org = create(:organization, :sponsorable, admin: member)
    other_item = other_org.sponsors_listing.featured_items.create(featureable: member)

    assert_equal [item], @listing.featured_items.reload
    assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
      @org.remove_member!(member)
    end

    assert_raises ActiveRecord::RecordNotFound do
      item.reload
    end

    # make sure featured items from other orgs still exist
    assert other_item.reload
  end

  context "validations" do
    test "sponsorable is org when featuring users" do
      user = create(:user, :sponsorable)
      item = build(:sponsors_listing_featured_item, sponsors_listing: user.sponsors_listing, featureable: user)

      refute_predicate item, :valid?
      assert_includes item.errors[:sponsorable], "must be an organization"
    end

    test "sponsorable users can feature repos" do
      user = create(:user, :sponsorable)
      repo = create(:repository, owner: user)
      item = build(:sponsors_listing_featured_item, sponsors_listing: user.sponsors_listing, featureable: repo)

      assert_predicate item, :valid?
    end

    test "featureable is present" do
      item = build(:sponsors_listing_featured_item, featureable: nil, sponsors_listing: @listing)

      refute_predicate item, :valid?
      assert_includes item.errors[:featureable], "must exist"
    end

    test "featureable should exist" do
      fake_user_id = T.must(T.must(User.order(:id).last).id) + 1
      item = build(:sponsors_listing_featured_item, sponsors_listing: @listing, featureable_id: fake_user_id)

      refute_predicate item, :valid?
      assert_includes item.errors[:featureable], "must exist"
    end

    test "featureable user is org member" do
      user = create(:user)
      item = build(:sponsors_listing_featured_item, sponsors_listing: @listing, featureable: user)

      refute_predicate item, :valid?
      assert_includes item.errors[:featureable], "must be a member of this organization"
    end

    test "featureable repo is owned by sponsorable" do
      repo = create(:repository)
      item = build(:sponsors_listing_featured_item, sponsors_listing: @listing, featureable: repo)

      refute_predicate item, :valid?
      assert_includes item.errors[:featureable], "must be owned by this organization"
    end

    test "featureable repo has contributions by sponsorable user" do
      sponsorable = create(:user, :sponsorable)
      repo = create(:repository)

      create(:commit_contribution, :with_summaries, repository: repo, user: sponsorable)
      item = sponsorable.sponsors_listing.featured_users.create(featureable: repo)

      assert_predicate item, :valid?
    end

    test "featureable repo is public" do
      repo = create(:private_repository, owner: @listing.sponsorable)
      item = build(:sponsors_listing_featured_item, sponsors_listing: @listing, featureable: repo)

      refute_predicate item, :valid?
      assert_includes item.errors[:featureable], "must be public"
    end

    test "featureable should be unique per listing" do
      repo = create(:repository, owner: @listing.sponsorable)
      item = @listing.featured_items.create(featureable: @org.admin)
      dup_item = @listing.featured_items.create(featureable: @org.admin)
      repo_item = @listing.featured_items.create(featureable: repo)
      dup_repo_item = @listing.featured_items.create(featureable: repo)

      assert_predicate item, :valid?
      refute_predicate dup_item, :valid?
      assert_includes dup_item.errors[:featureable_id], "has already been taken"
      assert_predicate repo_item, :valid?
      refute_predicate dup_repo_item, :valid?
      assert_includes dup_repo_item.errors[:featureable_id], "has already been taken"
    end

    test "featureable can repeat across listings" do
      other_org = create(:organization, :sponsorable, admin: @org.admin)

      item = @listing.featured_items.create(featureable: @org.admin)
      other_item = other_org.sponsors_listing.featured_items.create(featureable: @org.admin)

      assert_predicate item, :valid?
      assert_predicate other_item, :valid?
    end

    test "position should be a positive integer" do
      zero_position_item = @listing.featured_items.build(featureable: @org.admin, position: 0)
      negative_position_item = @listing.featured_items.build(featureable: @org.admin, position: -1)
      float_position_item = @listing.featured_items.build(featureable: @org.admin, position: 1.5)

      refute_predicate zero_position_item, :valid?
      assert_includes zero_position_item.errors[:position], "must be greater than 0"
      refute_predicate negative_position_item, :valid?
      assert_includes negative_position_item.errors[:position], "must be greater than 0"
      refute_predicate float_position_item, :valid?
      assert_includes float_position_item.errors[:position], "must be an integer"
    end

    test "description can be blank" do
      blank_description_item = @listing.featured_items.build(featureable: @org.admin, description: "")
      nil_description_item = @listing.featured_items.build(featureable: @org.admin, description: nil)

      assert_predicate blank_description_item, :valid?
      assert_predicate nil_description_item, :valid?
    end

    test "description must be less than #{SponsorsListingFeaturedItem::MAX_DESCRIPTION_LENGTH} characters" do
      short_description = "x" * SponsorsListingFeaturedItem::MAX_DESCRIPTION_LENGTH
      long_description = "x" * (SponsorsListingFeaturedItem::MAX_DESCRIPTION_LENGTH + 1)

      short_description_item = @listing.featured_items.build(featureable: @org.admin, description: short_description)
      long_description_item = @listing.featured_items.build(featureable: @org.admin, description: long_description)

      assert_predicate short_description_item, :valid?
      refute_predicate long_description_item, :valid?
      assert_includes long_description_item.errors[:description],
        "is too long (maximum is #{SponsorsListingFeaturedItem::MAX_DESCRIPTION_LENGTH} characters)"
    end

    test "listing can have up to #{SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING} featured users" do
      SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING.times do
        member = create(:user)
        @org.add_member(member)
        @listing.featured_items.create(featureable: member)
      end

      assert_equal SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING, @listing.featured_items.reload.count

      item = @listing.featured_items.build(featureable: @org.admin)

      refute_predicate item, :valid?
      assert_includes item.errors[:featured_users_count], "must be less than #{SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING}"
    end

    test "listing can have up to #{SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING} featured repos" do
      SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING.times do
        repo = create(:repository, owner: @listing.sponsorable)
        @listing.featured_items.create(featureable: repo)
      end

      assert_equal SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING, @listing.featured_items.reload.count

      other_repo = create(:repository, owner: @listing.sponsorable)
      item = @listing.featured_items.build(featureable: other_repo)

      refute_predicate item, :valid?
      assert_includes item.errors[:featured_repos_count], "must be less than #{SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING}"
    end

    test "listings can have the max number of featured users and repos at the same time" do
      SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING.times do
        member = create(:user)
        @org.add_member(member)
        @listing.featured_items.create(featureable: member)
      end

      SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING.times do
        repo = create(:repository, owner: @listing.sponsorable)
        @listing.featured_items.create(featureable: repo)
      end

      assert_equal SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING,
        @listing.featured_users.reload.count

      assert_equal SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING,
        @listing.featured_repos.reload.count
    end

    test "only paid or patreon sponsorships can be featured" do
      # While we only present paid/patreon sponsorships to maintainers as available for featuring,
      # we also want to rigorously enforce this constraint at the model level.
      paid_sponsorship = create(:sponsorship, :paid, sponsorable: @org)
      unpaid_sponsorship = create(:sponsorship, :unpaid, sponsorable: @org)
      paid_item = @listing.featured_items.create(featureable: paid_sponsorship)
      unpaid_item = @listing.featured_items.create(featureable: unpaid_sponsorship)

      assert_predicate paid_item, :valid?

      refute_predicate unpaid_item, :valid?
      assert_includes unpaid_item.errors[:featureable], "must be a paid or patreon sponsorship"
    end
  end
end
