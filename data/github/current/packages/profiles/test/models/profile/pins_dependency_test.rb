# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilePinsDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @user_profile = create(:profile, user: @user)

    @org = create(:organization)
    @org_profile = create(:profile, user: @org)
  end

  test "has many pinned repositories" do
    profile = create(:profile)

    repo1 = create(:repository, owner: profile.user)
    create(:profile_pin, profile: profile, pinned_item: repo1, position: 1)

    repo2 = create(:repository, owner: profile.user)
    create(:profile_pin, profile: profile, pinned_item: repo2, position: 2)

    assert_equal [repo1, repo2], profile.pinned_repositories
  end

  test "deletes pinned repository join records on destroy" do
    profile = create(:profile)
    pin = create(:profile_pin, profile: profile)
    profile.destroy
    refute ProfilePin.exists?(pin.id)
  end

  context "has_pins_for_all_items?" do
    test "true when given same items as are pinned" do
      profile = create(:profile)
      pin1 = create(:profile_pin, profile: profile, position: 1)
      pin2 = create(:profile_pin, :gist, profile: profile, position: 2)
      assert profile.has_pins_for_all_items?([pin1.pinned_item, pin2.pinned_item])
    end

    test "false when given an extra repository" do
      profile = create(:profile)
      repo = create(:repository, owner: profile.user)
      refute profile.has_pins_for_all_items?([repo])
    end

    test "false when given an extra gist" do
      profile = create(:profile)
      gist = create(:gist, user: profile.user)
      refute profile.has_pins_for_all_items?([gist])
    end

    test "false when missing a pinned repository" do
      profile = create(:profile)
      create(:profile_pin, profile: profile)
      refute profile.has_pins_for_all_items?([])
    end

    test "false when missing a pinned gist" do
      profile = create(:profile)
      create(:profile_pin, :gist, profile: profile)
      refute profile.has_pins_for_all_items?([])
    end

    test "true when given same items as are pinned for org" do
      pin1 = create(:profile_pin, profile: @org_profile, position: 1)
      pin2 = create(:profile_pin, profile: @org_profile, position: 2)
      assert @org_profile.has_pins_for_all_items?([pin1.pinned_item, pin2.pinned_item])
    end

    test "false when given same items as are pinned for org in different view" do
      pin1 = create(:profile_pin, profile: @org_profile, position: 1, internal_view: true)
      pin2 = create(:profile_pin, profile: @org_profile, position: 2, internal_view: true)
      refute @org_profile.has_pins_for_all_items?([pin1.pinned_item, pin2.pinned_item], internal_view: false)
    end
  end

  context "pin_items" do
    test "creates new profile pins" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      gist = create(:gist, user: user)
      assert_difference("profile.profile_pins.count", 2) do
        profile.pin_items([repo, gist])
      end
    end

    test "deletes existing pins whose repos and gists were not passed in" do
      user = create(:user)
      profile = create(:profile, user: user)

      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)
      gist1 = create(:gist, user: user)
      gist2 = create(:gist, user: user)

      pin1 = create(:profile_pin, profile: profile, pinned_item: repo1)
      pin2 = create(:profile_pin, profile: profile, pinned_item: repo2)
      pin3 = create(:profile_pin, profile: profile, pinned_item: gist1)
      pin4 = create(:profile_pin, profile: profile, pinned_item: gist2)

      assert_difference("ProfilePin.count", -2) do
        profile.pin_items([repo1, gist2])
      end

      assert ProfilePin.exists?(pin1.id)
      refute ProfilePin.exists?(pin2.id)
      refute ProfilePin.exists?(pin3.id)
      assert ProfilePin.exists?(pin4.id)
    end

    test "handles both creation and deletion at once" do
      user = create(:user)
      profile = create(:profile, user: user)

      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)
      repo3 = create(:repository, owner: user)
      gist1 = create(:gist, user: user)

      pin1 = create(:profile_pin, profile: profile, pinned_item: repo2, position: 2)
      pin2 = create(:profile_pin, profile: profile, pinned_item: repo3, position: 3)

      # Should create two and delete one:
      assert_difference("ProfilePin.count") do
        profile.pin_items([repo1, repo3, gist1])
      end

      new_pin1 = ProfilePin.for_profile(profile).for_repository(repo1).first
      refute_nil new_pin1, "should have added a new pin for repo that was not pinned before"
      new_pin2 = ProfilePin.for_profile(profile).for_gist(gist1).first
      refute_nil new_pin2, "should have added a new pin for gist that was not pinned before"
      assert_equal [T.must(new_pin1).position, pin2.reload.position, T.must(new_pin2).position],
        [T.must(new_pin1).position, pin2.reload.position, T.must(new_pin2).position].sort,
        "should have new_pin1, then pin2, then new_pin2"
      assert_equal [repo1, repo3, gist1],
        [T.must(new_pin1).pinned_item, pin2.pinned_item, T.must(new_pin2).pinned_item]
      refute ProfilePin.exists?(pin1.id),
        "should have removed pin for repo that was not passed in new pin list"
    end

    test "does not create duplicate positions" do
      profile = create(:profile)

      repo1 = create(:repository, owner: profile.user, name: "repo1")
      repo2 = create(:repository, owner: profile.user, name: "repo2")
      repo3 = create(:repository, owner: profile.user, name: "repo3")

      pin1 = create(:profile_pin, profile: profile, pinned_item: repo1, position: 1)
      pin2 = create(:profile_pin, profile: profile, pinned_item: repo2, position: 2)

      # Should create one and delete another
      assert_no_difference "ProfilePin.count" do
        profile.pin_items([repo2, repo3])
      end

      refute ProfilePin.exists?(pin1.id),
        "should have removed pin for repo that was not given in new list"
      assert_equal 2, pin2.reload.position, "should not change existing pin's position"
      new_pin = ProfilePin.for_profile(profile).for_repository(repo3).first
      refute_nil new_pin,
        "should have created a new ProfilePin for repo in given list"
      assert_equal [pin2.position, T.must(new_pin).position],
        [pin2.position, T.must(new_pin).position].sort,
        "should be in the order with pin2 first, then new_pin"
    end

    test "will not pin inactive repositories" do
      repo = create(:repository, owner: @user, active: nil)

      assert_no_difference "ProfilePin.count" do
        @user_profile.pin_items([repo])
      end
    end

    test "will not pin private repositories" do
      repo = create(:private_repository, owner: @user)

      assert_no_difference "ProfilePin.count" do
        @user_profile.pin_items([repo])
      end
    end

    test "will not pin secret gists" do
      gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: @user,
                           public: false)

      assert_no_difference "ProfilePin.count" do
        @user_profile.pin_items([gist])
      end
    end

    test "will not pin disabled repositories" do
      repo1 = create(:repository, owner: @user)
      create(:disabled_access_reason, flagged_item: repo1)
      repo2 = create(:repository, owner: @user, disabled_at: 1.week.ago)

      assert_no_difference "ProfilePin.count" do
        @user_profile.pin_items([repo1, repo2])
      end
    end

    test "will not pin disabled gists" do
      gist2 = create(:gist, user: @user, disabled_at: 1.week.ago)

      assert_no_difference "ProfilePin.count" do
        @user_profile.pin_items([gist2])
      end
    end

    test "handles both creation and deletion at once for org with pins in both views" do
      org = create(:organization)
      org_profile = create(:profile, user: org)

      repo1 = create(:repository, owner: org)
      repo2 = create(:repository, owner: org)
      repo3 = create(:repository, owner: org)

      pin1 = create(:profile_pin, profile: org_profile, pinned_item: repo2, position: 2, internal_view: true)
      pin2 = create(:profile_pin, profile: org_profile, pinned_item: repo3, position: 3, internal_view: false)

      # Should create two and delete one:
      assert_difference("ProfilePin.count") do
        org_profile.pin_items([repo1, repo3], internal_view: true)
      end

      new_pin1 = ProfilePin.for_profile(org_profile).for_repository(repo1).first
      refute_nil new_pin1, "should have added a new pin for repo that was not pinned before"
      new_pin2 = ProfilePin.for_profile(org_profile).for_repository(repo3).first
      refute_nil new_pin2, "should have added a new pin for repo that was not pinned before in internal view"
      refute ProfilePin.exists?(pin1.id),
        "should have removed pin for repo that was not passed in new pin list"
    end

  end

  context "#create_profile_pin" do
    test "creates new pinned repositories" do
      profile = create(:profile)
      repo = create(:repository, owner: profile.user)

      assert_difference("profile.profile_pins.repositories.count") do
        profile.create_profile_pin(pinned_item_id: repo.id, pinned_item_type: :Repository,
                                   position: 4)
      end
    end

    test "finds existing profile pinned repositories" do
      profile = create(:profile)
      repo = create(:repository, owner: profile.user)
      pin_params = { pinned_item_id: repo.id, pinned_item_type: :Repository, position: 4 }
      profile.create_profile_pin(**pin_params)

      assert_no_difference("ProfilePin.count") do
        assert profile.create_profile_pin(**pin_params),
          "should return true to indicate the pin exists as describes"
      end
    end

    test "logs Hydro event for a user with a repo" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      repo = create(:repository, owner: @user)

      @user_profile.create_profile_pin(pinned_item_id: repo.id, pinned_item_type: :Repository,
                                       position: 1)

      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: 1,
        repository_id: repo.id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end

    test "logs Hydro event for an org with a repo" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      repo = create(:repository, owner: @org)

      @org_profile.create_profile_pin(pinned_item_id: repo.id, pinned_item_type: :Repository,
                                      position: 1)

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        position: 1,
        repository_id: repo.id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end

    test "logs Hydro event for a user with a gist" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      gist = create(:gist, user: @user)

      @user_profile.create_profile_pin(pinned_item_id: gist.id, pinned_item_type: :Gist,
                                       position: 1)

      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: 1,
        gist_id: gist.id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end
  end

  context "reorder_pinned_items" do
    test "updates position of existing pinned repos" do
      profile = create(:profile)

      repo1 = create(:repository, owner: profile.user)
      repo2 = create(:repository, owner: profile.user)
      repo3 = create(:repository, owner: profile.user)

      pin1 = create(:profile_pin, profile: profile, pinned_item: repo1, position: 1)
      pin2 = create(:profile_pin, profile: profile, pinned_item: repo2, position: 2)
      pin3 = create(:profile_pin, profile: profile, pinned_item: repo3, position: 3)

      assert_no_difference("ProfilePin.count") do
        profile.reorder_pinned_items([repo3, repo1, repo2])
      end

      assert_equal 1, pin3.reload.position
      assert_equal 2, pin1.reload.position
      assert_equal 3, pin2.reload.position
    end

    test "updates position of existing pinned repos for org" do
      org = create(:organization)
      org_profile = create(:profile, user: org)

      repo1 = create(:repository, owner: org)
      repo2 = create(:repository, owner: org)
      repo3 = create(:repository, owner: org)

      pin1 = create(:profile_pin, profile: org_profile, pinned_item: repo1, position: 1, internal_view: true)
      pin2 = create(:profile_pin, profile: org_profile, pinned_item: repo2, position: 2, internal_view: true)
      pin3 = create(:profile_pin, profile: org_profile, pinned_item: repo3, position: 3, internal_view: false)

      assert_no_difference("ProfilePin.count") do
        org_profile.reorder_pinned_items([repo2, repo1], internal_view: true)
      end

      assert_equal 1, pin2.reload.position
      assert_equal 2, pin1.reload.position
    end

    test "returns false when given repository IDs that aren't pinned" do
      profile = create(:profile)
      repo = create(:repository, owner: profile.user)

      assert_no_difference("ProfilePin.count") do
        profile.reorder_pinned_items([repo])
      end
    end
  end

  context "#pinned_repositories" do
    test "includes profile_pins" do
      profile = create(:profile)
      profile_pin = create(:profile_pin, profile: profile, position: 2)
      profile_pin2 = create(:profile_pin, profile: profile, position: 3)

      assert_equal [profile_pin.pinned_item, profile_pin2.pinned_item],
        profile.pinned_repositories
    end

    test "returns an empty list when profile has no pinned repos" do
      profile = create(:profile)
      create(:profile_pin, :gist, profile: profile)

      assert_empty profile.pinned_repositories
    end
  end

  test "deletes pins on destroy" do
    profile = create(:profile)
    pin = create(:profile_pin, profile: profile)

    assert_difference("ProfilePin.count", -1) do
      profile.destroy
    end

    refute ProfilePin.exists?(pin.id)
  end
end
