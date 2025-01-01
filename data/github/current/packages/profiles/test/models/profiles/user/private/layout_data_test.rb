# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilesUserPrivateLayoutDataTest < GitHub::TestCase
  fixtures do
    @profile_user = create(:user)
    @viewer = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
  end

  context ".preload" do
    test "it prefetches all of the data in the minimal amount of queries" do
      assert_max_query_count(14) do
        Profiles::User::Private::LayoutData.preload(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)
      end
    end

    test "it prefetches all the data except for the sponsors methods in the minimal amount of queries" do
      assert_max_query_count(12) do
        Profiles::User::Private::LayoutData.preload(
          profile_user: @profile_user,
          viewer: @viewer,
          active_tab: :stars,
        )
      end
    end

    test "no queries are made after the data is preloaded" do
      layout_data = Profiles::User::BaseLayoutData.preload(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

      assert_max_query_count(0) do
        Profiles::User::BaseLayoutData::METHODS_TO_PRELOAD.each do |method|
          layout_data.send(method)
        end
      end
    end
  end
end
