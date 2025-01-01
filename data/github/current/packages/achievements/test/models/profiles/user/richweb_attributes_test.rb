# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilesUserRichwebAttributesTest < GitHub::TestCase
  fixtures do
    @profile_user, @viewer = create_pair(:user)
  end

  setup do
    @layout_data = Profiles::User::LayoutData.preload(
      profile_user: @profile_user,
      viewer: @viewer,
      active_tab: :achievements,
    )
  end

  context ".build" do
    test "returns a hash of richweb attributes for a request to achievements show" do
      achievement = create(:achievement, :pull_shark, user: @profile_user, unlocked_at: Time.now)
      expected_attributes = {
        title: "#{@profile_user} / Achievements",
        description: "@#{@profile_user} opened pull requests that have been merged.",
        updated_time: achievement.unlocked_at,
        image: "#{GitHub.asset_host_url}/images/modules/profile/achievements/social-cards/pull-shark-default.png",
        card: "summary",
      }

      richweb_attributes = Profiles::User::RichwebAttributes.build(@layout_data, achievement, [])

      assert_equal expected_attributes, richweb_attributes
    end

    test "returns a hash of richweb attributes for a request to achievements show for a legacy achievable" do
      highlight = create(
        :profile_highlight,
        user: @profile_user,
        highlight_type: :nasa_2020,
        hidden: false,
        eligible: true,
      )
      achievement = @profile_user.achievements.new(
        achievable_slug: Achievable::Mars2020Contributor.slug,
        tier: 0,
        seen_at: Time.now,
      )

      expected_attributes = {
        title: "#{@profile_user} / Achievements",
        description: "@#{@profile_user} contributed code to 0 repositories used in the Mars 2020 Helicopter Mission.",
        updated_time: achievement.unlocked_at,
        image: "#{GitHub.asset_host_url}/images/modules/profile/achievements/social-cards/mars-2020-contributor-default.png",
        card: "summary",
      }

      richweb_attributes = Profiles::User::RichwebAttributes.build(@layout_data, achievement, [])

      assert_equal expected_attributes, richweb_attributes
    end

    test "returns a hash of richweb attributes for a request to achievements index" do
      expected_attributes = {
        title: "#{@profile_user} - Achievements",
        url: "https://github.com/#{@profile_user}",
        image: "http://alambic.github.test/avatars/u/#{@profile_user.id}?b=1&v=2?s=400",
        username: @profile_user.login,
        description: "GitHub is where #{@profile_user} builds software.",
        type: "profile",
        card: "summary",
      }

      richweb_attributes = Profiles::User::RichwebAttributes.build(@layout_data, nil, [])

      assert_equal expected_attributes, richweb_attributes
    end
  end
end
