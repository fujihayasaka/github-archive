# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilesUserLayoutDataTest < GitHub::TestCase
  fixtures do
    @profile_user = create(:user)
    @viewer = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
  end

  setup do
    GitHub.flipper[:proxima_emus_omit_profile_star_count].disable
  end

  context ".preload" do
    test "it prefetches all of the data in the minimal amount of queries" do
      assert_max_query_count(15, ignore_feature_flags: true) do
        Profiles::User::LayoutData.preload(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)
      end
    end

    test "it prefetches all the data except for the sponsors methods in the minimal amount of queries" do
      assert_max_query_count(12, ignore_feature_flags: true) do
        Profiles::User::LayoutData.preload(
          profile_user: @profile_user,
          viewer: @viewer,
          skip_sponsor_preloads: true,
          active_tab: :stars,
        )
      end
    end

    test "no queries are made after the data is preloaded" do
      layout_data = Profiles::User::LayoutData.preload(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

      assert_max_query_count(0) do
        Profiles::User::LayoutData::METHODS_TO_PRELOAD.each do |method|
          layout_data.send(method)
        end
      end
    end
  end

  test "it runs 0 queries for bounty_hunter?, campus_expert?, and github_star?" do
    create(:user_metadata, user: @profile_user)
    data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

    assert_max_query_count(0) do
      data.bounty_hunter?
      data.campus_expert?
      data.github_star?
    end
  end unless GitHub.enterprise?

  context "#active_sponsorships_as_sponsor" do
    test "includes private sponsorship from the profile user when viewer is that user" do
      sponsorship = create(:sponsorship, :private)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: sponsorship.sponsor,
        active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "includes private sponsorship from the profile user when viewer is the maintainer being sponsored" do
      sponsorship = create(:sponsorship, :private)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: sponsorship.sponsorable,
        active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "includes private sponsorship from the profile user when viewer belongs to the org being sponsored" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org.add_member(@viewer)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: @viewer,
        active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "includes private sponsorship from the profile user when viewer is admin of the org being sponsored" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: org.admins.first,
        active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "omits private sponsorship from the profile user when viewer is billing manager of the org being sponsored" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org.billing.add_manager(@viewer, actor: org.admins.first)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: @viewer, active_tab: :other)
      refute_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "includes public sponsorship from the profile user when viewer is that user" do
      sponsorship = create(:sponsorship)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: sponsorship.sponsor,
        active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "includes public sponsorship from the profile user when viewer is anonymous" do
      sponsorship = create(:sponsorship)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: nil, active_tab: :other)
      assert_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "omits private sponsorship from the profile user when viewer is anonymous" do
      sponsorship = create(:sponsorship, :private)
      data = Profiles::User::LayoutData.new(profile_user: sponsorship.sponsor, viewer: nil, active_tab: :other)
      refute_includes data.active_sponsorships_as_sponsor, sponsorship
    end

    test "omits unpaid sponsorships" do
      unpaid_sponsorship = create(:sponsorship, :unpaid)

      data = Profiles::User::LayoutData.new(profile_user: unpaid_sponsorship.sponsor, viewer: nil, active_tab: :other)
      refute_includes data.active_sponsorships_as_sponsor, unpaid_sponsorship
    end
  end if GitHub.sponsors_enabled?

  context "#show_follow_button?" do
    test "it returns false when the profile user is the viewer" do
      data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @profile_user,
        active_tab: :stars)
      refute_predicate data, :show_follow_button?
    end

    test "it returns true when the viewer is not on their own profile" do
      data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer,
        active_tab: :stars)
      assert_predicate data, :show_follow_button?
    end

    test "it returns true for an anonymous viewer" do
      data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: nil,
        active_tab: :stars)
      assert_predicate data, :show_follow_button?
    end
  end

  context "#sponsoring_count" do
    if GitHub.sponsors_enabled?
      test "returns public and private active sponsorships when profile user is the viewer" do
        user = create(:user)
        create(
          :user_metadata,
          user: user,
          sponsoring_public_and_private_count: 10,
          sponsoring_count: 5,
          inactive_sponsoring_count: 1,
          inactive_sponsoring_public_and_private_count: 2,
        )

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: user,
          active_tab: :overview,
        )

        assert_equal data.sponsoring_count, 10
      end

      test "returns only public active sponsorships when viewer is not the profile user" do
        user = create(:user)
        create(
          :user_metadata,
          user: user,
          sponsoring_public_and_private_count: 10,
          sponsoring_count: 5,
          inactive_sponsoring_count: 1,
          inactive_sponsoring_public_and_private_count: 2,
        )

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_equal data.sponsoring_count, 5
      end

      test "returns only public active sponsorships when viewer is logged out" do
        user = create(:user)
        create(
          :user_metadata,
          user: user,
          sponsoring_public_and_private_count: 10,
          sponsoring_count: 5,
          inactive_sponsoring_count: 1,
          inactive_sponsoring_public_and_private_count: 2,
        )

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: nil,
          active_tab: :overview,
        )

        assert_equal data.sponsoring_count, 5
      end
    end
  end

  context "#show_sponsor_button?" do
    if GitHub.sponsors_enabled?
      test "it returns false when the profile user is the viewer" do
        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @profile_user, active_tab: :stars)

        refute_predicate data, :show_sponsor_button?
      end

      test "it returns true even when the viewer is blocking the profile user" do
        assert @viewer.block(@profile_user)
        create(:sponsors_listing, :approved, sponsorable: @profile_user)

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer,
          active_tab: :stars)

        assert_predicate data, :show_sponsor_button?
      end

      test "it returns true even when the profile user is blocking the viewer" do
        assert @profile_user.block(@viewer)
        create(:sponsors_listing, :approved, sponsorable: @profile_user)

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer,
          active_tab: :stars)

        assert_predicate data, :show_sponsor_button?
      end

      test "it returns true when the viewer is sponsoring the profile user" do
        sponsors_listing = create(
          :sponsors_listing,
          :approved,
          tier_count: 3,
          sponsorable: @profile_user,
        )
        create(
          :sponsorship,
          sponsorable: @profile_user,
          tier: sponsors_listing.default_tier,
          sponsor: @viewer,
        )

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

        assert_predicate data, :show_sponsor_button?
      end

      test "it returns false when the viewer is sponsoring the profile user but the sponsors listing is SDN disabled" do
        GitHub.flipper[:live_sdn_screening].enable(@profile_user)

        sponsors_listing = create(
          :sponsors_listing,
          :approved,
          tier_count: 3,
          sponsorable: @profile_user,
        )
        create(
          :sponsorship,
          sponsorable: @profile_user,
          tier: sponsors_listing.default_tier,
          sponsor: @viewer,
        )

        sponsors_listing.sdn_disable!

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

        refute_predicate data, :show_sponsor_button?
      end

      test "it returns true when the profile user is sponsorable" do
        create(
          :sponsors_listing,
          :approved,
          tier_count: 3,
          sponsorable: @profile_user,
        )

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

        assert_predicate data, :show_sponsor_button?
      end

      test "it returns false when the profile users sponsor listing is SDN disabled" do
        create(
          :sponsors_listing,
          :sdn_disabled,
          sponsorable: @profile_user,
        )

        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

        refute_predicate data, :show_sponsor_button?
      end
    else
      test "it returns false" do
        data = Profiles::User::LayoutData.new(profile_user: @profile_user, viewer: @viewer, active_tab: :stars)

        refute_predicate data, :show_sponsor_button?
      end
    end
  end

  context "#stars_count" do
    context "when a metadata record exists for the user" do
      test "it returns the metadata stars_count value with 1 query" do
        user = create(:user)
        create(:user_metadata, stars_count: 10, user: user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(0) do
          assert_equal 10, data.stars_count
        end
      end

      test "it still returns the metadata stars_count value with 1 query when the proxima_emus_omit_profile_star_count FF is enabled for the viewer", skip_in_multitenant_mode: true do
        user = create(:user)
        # Realistically the stars_count value will always be 0, as any repos the user has starred will be private or internal.
        create(:user_metadata, stars_count: 10, stars_public_and_private_count: 42, user: user)

        GitHub.flipper[:proxima_emus_omit_profile_star_count].enable(@viewer)
        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(0) do
          assert_equal 10, data.stars_count
        end
      end

      context "on proxima", skip_unless: :proxima_emu_test_mode? do
        test "it returns the metadata stars_count value with 1 query when the proxima_emus_omit_profile_star_count FF is disabled for the viewer" do
          user = create(:user)
          # Realistically the stars_count value will always be 0, as any repos the user has starred will be private or internal.
          create(:user_metadata, stars_count: 10, stars_public_and_private_count: 42, user: user)

          data = Profiles::User::LayoutData.new(
            profile_user: user,
            viewer: @viewer,
            active_tab: :overview,
          )

          assert_max_query_count(0) do
            assert_equal 10, data.stars_count
          end
        end

        test "it returns a hard-coded 0 value with 1 query when the proxima_emus_omit_profile_star_count FF is enabled for the viewer" do
          user = create(:user)
          create(:user_metadata, stars_count: 10, stars_public_and_private_count: 42, user: user)

          GitHub.flipper[:proxima_emus_omit_profile_star_count].enable(@viewer)
          data = Profiles::User::LayoutData.new(
            profile_user: user,
            viewer: @viewer,
            active_tab: :overview,
          )

          assert_max_query_count(0) do
            assert_equal 0, data.stars_count
          end
        end
      end
    end

    context "when a metadata record does not exist for the user" do
      test "it returns 0 with 1 query" do
        user = create(:user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(1) do
          assert_equal 0, data.stars_count
        end
      end
    end
  end

  context "#followers_count" do
    context "when a metadata record exists for the user" do
      test "it returns the metadata followers_count value with up to 2 queries" do
        user = create(:user)
        create(:user_metadata, followers_count: 10, user: user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(2) do
          assert_equal 10, data.followers_count
        end
      end
    end

    context "when a metadata record does not exist for the user" do
      test "it returns 0 with up to 3 queries" do
        user = create(:user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(3) do
          assert_equal 0, data.followers_count
        end
      end
    end
  end

  context "#following_count" do
    context "when a metadata record exists for the user" do
      test "it returns the metadata following_count value with up to 2 queries" do
        user = create(:user)
        create(:user_metadata, following_count: 10, user: user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(2) do
          assert_equal 10, data.following_count
        end
      end
    end

    context "when a metadata record does not exist for the user" do
      test "it returns 0 with up to 3 queries" do
        user = create(:user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_max_query_count(3) do
          assert_equal 0, data.following_count
        end
      end
    end

    context "repo_column" do
      test "when a viewer is viewing their own profile returns the full repo count" do
        user = create(:user)
        create(:user_metadata, repository_public_and_private_count: 10, repository_count: 0, user: user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: user,
          active_tab: :overview,
        )

        assert_equal data.repository_count, 10
      end

      test "when a viewer is viewing another profile returns the public repo count" do
        user = create(:user)
        create(:user_metadata, repository_public_and_private_count: 10, repository_count: 0, user: user)

        data = Profiles::User::LayoutData.new(
          profile_user: user,
          viewer: @viewer,
          active_tab: :overview,
        )

        assert_equal data.repository_count, 0
      end
    end
  end
end
