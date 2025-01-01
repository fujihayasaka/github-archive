# typed: true
# frozen_string_literal: true

require "test_helper"

class UserMetadataTest < GitHub::TestCase
  test "validates presence of user" do
    user_metadata = create(:user_metadata)
    user_metadata.user = nil

    assert_equal user_metadata.valid?, false
  end

  context "#achievables_and_tiers" do
    test "returns data based on the order and data from :achievement_public_slugs" do
      user = create(:user)
      slugs = [
        Achievable::Heartbreaker.slug + ":0",
        Achievable::PullShark.slug + ":2",
        "something-we-renamed:3",
        Achievable::Yolo.slug + ":0"
      ].join(",")
      user_metadata = create(:user_metadata, user: user, achievement_public_slugs: slugs)

      results = [
        [Achievable::Heartbreaker.instance, 0],
        [Achievable::PullShark.instance, 2],
        [Achievable::Yolo.instance, 0],
      ]
      assert_equal results, user_metadata.achievables_and_tiers(visibility: :PUBLIC)
    end

    test "returns data based on the order and data from :achievement_private_slugs" do
      user = create(:user)
      slugs = [
        Achievable::OpenSourcerer.slug + ":1",
        "something-we-deleted:3",
        Achievable::DustBunny.slug + ":0",
        Achievable::PullShark.slug + ":1",
      ].join(",")
      user_metadata = create(:user_metadata, user: user, achievement_private_slugs: slugs)

      results = [
        [Achievable::OpenSourcerer.instance, 1],
        [Achievable::DustBunny.instance, 0],
        [Achievable::PullShark.instance, 1],
      ]
      assert_equal results, user_metadata.achievables_and_tiers(visibility: :PRIVATE)
    end
  end

  test "#has_mars_badge? returns true when there is a nasa_2020 highlight that is eligible and not hidden" do
    user = create(:user)
    user_metadata = create(:user_metadata, user: user)
    create(
      :profile_highlight,
      user: user,
      highlight_type: :nasa_2020,
      eligible: true,
      hidden: false,
    )

    assert_predicate user.user_metadata, :has_mars_badge?
  end
end
