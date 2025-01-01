# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseBannerDismissalTest < GitHub::TestCase
  # Tests also exist in enterprise_banner_test.rb

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @business = create(:business, owners: [@user], organizations: [@org])
  end

  test "can dismiss dismissible banners" do
    dismissible_banner = create(:enterprise_banner, owner: @business, dismissible: true)
    assert_equal true, dismissible_banner.dismissible

    dismissible_banner.dismiss(@user)
    refute_nil EnterpriseBannerDismissal.find_by(enterprise_banner: dismissible_banner, user: @user)

    standard_banner = create(:enterprise_banner, owner: @repo, expires_at: 1.day.from_now)
    assert_equal false, standard_banner.dismissible

    standard_banner.dismiss(@user)
    if GitHub::flipper.enabled?(:minimize_announcements)
      # dismissing a non-dismissible banner minimizes it on the screen instead of completely hiding it
      # so we still expect a record in the EnterpriseBannerDismissal table to store the user's preference
      # that this banner be minimized
      refute_nil EnterpriseBannerDismissal.find_by(enterprise_banner: standard_banner, user: @user)
    else
      assert_nil EnterpriseBannerDismissal.find_by(enterprise_banner: standard_banner, user: @user)
    end
  end
end
