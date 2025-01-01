# typed: false
# frozen_string_literal: true

require "test_helper"

class ProfilePinTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user)
    @user_profile = create(:profile, user: @user)
    @staff_admin_user = create(:staff_admin_user)

    @org = create(:organization)
    @org_profile = create(:profile, user: @org)

    @normal_repo = create(:repository, owner: @user)
    @normal_repo_pin = create(:profile_pin, pinned_item: @normal_repo, profile: @user_profile)

    gist_contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate(contents: gist_contents, user: @user)
    @gist_pin = create(:profile_pin, pinned_item: @gist, profile: @user_profile)
  end

  context "Hydro events" do
    test "logs event on creation for a repo pin from a user", skip_enterprise: true do
      pin = create(:profile_pin, profile: @user_profile)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        repository_id: pin.pinned_item_id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end

    test "logs event on creation for a repo pin from an organization", skip_enterprise: true do
      pin = create(:profile_pin, profile: @org_profile, internal_view: true)
      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        position: pin.position,
        repository_id: pin.pinned_item_id,
        internal_view: pin.internal_view,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end

    test "logs event on creation for a gist pin from a user", skip_enterprise: true do
      pin = create(:profile_pin, :gist, profile: @user_profile)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        gist_id: pin.pinned_item_id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinCreate")
    end

    test "logs event on deletion for a repo pin from a user", skip_enterprise: true do
      @normal_repo_pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: @normal_repo_pin.position,
        repository_id: @normal_repo_pin.pinned_item_id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinDestroy")
    end

    test "logs event on deletion for a repo pin from an organization", skip_enterprise: true do
      pin = create(:profile_pin, profile: @org_profile, internal_view: true)
      pin.destroy
      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        position: pin.position,
        repository_id: pin.pinned_item_id,
        internal_view: pin.internal_view,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinDestroy")
    end

    test "logs event on deletion for a gist pin from a user", skip_enterprise: true do
      @gist_pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: @gist_pin.position,
        gist_id: @gist_pin.pinned_item_id,
      }
      assert_hydro_published(message, schema: "github.v1.ProfilePinDestroy")
    end
  end

  context "validations" do
    test "disallows a profile for a bot" do
      bot = create(:bot)
      profile = create(:profile, user: bot)

      repo = create(:repository)
      pin = build(:profile_pin, profile: profile, pinned_item: repo)

      refute_predicate pin, :valid?
      assert_includes pin.errors[:profile], "must belong to a user or organization"
    end

    test "disallows a profile for an organization when pinning a gist" do
      org = create(:organization)
      profile = create(:profile, user: org)
      pin = build(:profile_pin, :gist, profile: profile)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:profile], "must belong to a user for pinning a gist"
    end

    test "requires a profile" do
      profile_pin = ProfilePin.new
      refute_predicate profile_pin, :valid?
      assert_includes profile_pin.errors[:profile], "can't be blank"
    end

    test "requires a pinned_item_type" do
      profile_pin = ProfilePin.new
      refute_predicate profile_pin, :valid?
      assert_includes profile_pin.errors[:pinned_item_type], "can't be blank"
    end

    test "requires a pinned_item_id" do
      profile_pin = ProfilePin.new
      refute_predicate profile_pin, :valid?
      assert_includes profile_pin.errors[:pinned_item_id], "can't be blank"
    end

    test "allows 6 pins per profile" do
      profile = create(:profile)
      last_profile_pin = nil
      6.times do
        last_profile_pin = create(:profile_pin, profile: profile)
      end
      profile_pin = build(:profile_pin, profile: profile)
      refute profile_pin.valid?, "seventh pin should not be valid"
      assert_includes profile_pin.errors.full_messages,
        "Total pins for your profile cannot exceed 6"
    end

    test "requires a unique item per profile" do
      gist = create(:gist)
      profile = create(:profile, user: gist.user)
      create(:profile_pin, pinned_item: gist, profile: profile)

      profile_pin = build(:profile_pin, pinned_item: gist, profile: profile, position: 2)

      refute_predicate profile_pin, :valid?
      assert_includes profile_pin.errors[:pinned_item_id], "has already been taken"
    end

    test "disallows pinning a private repository in public view" do
      private_repo = create(:private_repository)
      pin = build(:profile_pin, pinned_item: private_repo, internal_view: false)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must be public in public view"
    end

    test "allows pinning a private repository in internal view" do
      private_repo = create(:private_repository)
      pin = build(:profile_pin, pinned_item: private_repo, internal_view: true)
      assert_predicate pin, :valid?
      refute_includes pin.errors[:pinned_item], "must be public in public view"
    end

    test "disallows pinning a secret gist" do
      secret_gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: @user,
                                  public: false)
      pin = build(:profile_pin, pinned_item: secret_gist)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must be public in public view"
    end

    test "disallows pinning an inactive repository" do
      inactive_repo = create(:repository, active: nil)
      pin = build(:profile_pin, pinned_item: inactive_repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must be active"
    end

    test "disallows pinning a disabled repository" do
      repo = create(:repository, disabled_at: 1.week.ago)
      pin = build(:profile_pin, pinned_item: repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a disabled gist" do
      gist = create(:gist, disabled_at: 1.week.ago)
      pin = build(:profile_pin, pinned_item: gist)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a repository with a disabled access reason" do
      repo = create(:repository, disabled_at: Time.now, disabling_reason: "size")
      pin = build(:profile_pin, pinned_item: repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a gist with a disabled access reason" do
      gist = create(:gist, disabled_at: Time.now, disabling_reason: "size")
      pin = build(:profile_pin, pinned_item: gist)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end
  end

  context "not_repositories scope" do
    test "includes only gist pins" do
      repo_pin = create(:profile_pin)
      gist_pin = create(:profile_pin, :gist)

      result = ProfilePin.not_repositories

      refute_includes result, repo_pin
      assert_includes result, gist_pin
    end
  end

  context "not_gists scope" do
    test "includes only repository pins" do
      repo_pin = create(:profile_pin)
      gist_pin = create(:profile_pin, :gist)

      result = ProfilePin.not_gists

      assert_includes result, repo_pin
      refute_includes result, gist_pin
    end
  end

  context "repositories scope" do
    test "includes only repository pins" do
      repo_pin = create(:profile_pin)
      gist_pin = create(:profile_pin, :gist)

      result = ProfilePin.repositories

      assert_includes result, repo_pin
      refute_includes result, gist_pin
    end
  end

  context "gists scope" do
    test "includes only gist pins" do
      repo_pin = create(:profile_pin)
      gist_pin = create(:profile_pin, :gist)

      result = ProfilePin.gists

      refute_includes result, repo_pin
      assert_includes result, gist_pin
    end
  end

  context "for_profile scope" do
    test "includes only pins for the given profile" do
      profile1 = create(:profile)
      profile2 = create(:profile)
      profile1_pin1 = create(:profile_pin, profile: profile1)
      profile2_pin1 = create(:profile_pin, profile: profile2)
      profile1_pin2 = create(:profile_pin, :gist, profile: profile1, position: 2)
      profile2_pin2 = create(:profile_pin, :gist, profile: profile2, position: 2)

      result = ProfilePin.for_profile(profile2)

      assert_includes result, profile2_pin1
      assert_includes result, profile2_pin2
      refute_includes result, profile1_pin1
      refute_includes result, profile1_pin2
    end
  end

  context "ordered_by_position scope" do
    test "returns the pins in ascending order by position" do
      profile = create(:profile)
      profile_pin1 = create(:profile_pin, profile: profile, position: 2)
      profile_pin2 = create(:profile_pin, profile: profile, position: 1)
      profile_pin3 = create(:profile_pin, profile: profile, position: 3)

      assert_equal [profile_pin2, profile_pin1, profile_pin3],
        ProfilePin.for_profile(profile).ordered_by_position
    end
  end

  context "#pinned_item=" do
    test "sets pinned_item_type and pinned_item_id for the given repo" do
      profile_pin = ProfilePin.new

      profile_pin.pinned_item = @normal_repo

      assert_equal @normal_repo.id, profile_pin.pinned_item_id
      assert_equal "Repository", profile_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given gist" do
      gist = create(:gist)
      profile_pin = ProfilePin.new

      profile_pin.pinned_item = gist

      assert_equal gist.id, profile_pin.pinned_item_id
      assert_equal "Gist", profile_pin.pinned_item_type
    end
  end

  context "#pinned_item" do
    test "returns the repository when pinned_item_type is Repository" do
      repo = create(:repository, owner: @user)
      pin = ProfilePin.create!(pinned_item_type: "Repository", pinned_item_id: repo.id,
                               profile_id: @user_profile.id)
      assert_equal repo, pin.pinned_item
    end

    test "returns the gist when pinned_item_type is Gist" do
      gist = create(:gist, user: @user)
      pin = ProfilePin.create!(pinned_item_type: "Gist", pinned_item_id: gist.id,
                               profile_id: @user_profile.id)
      assert_equal gist, pin.pinned_item
    end
  end

  context "#repository?" do
    test "true for repo pin" do
      pin = create(:profile_pin)
      assert_predicate pin, :repository?
    end

    test "false for gist pin" do
      pin = create(:profile_pin, :gist)
      refute_predicate pin, :repository?
    end
  end

  context "#gist?" do
    test "false for repo pin" do
      pin = create(:profile_pin)
      refute_predicate pin, :gist?
    end

    test "true for gist pin" do
      pin = create(:profile_pin, :gist)
      assert_predicate pin, :gist?
    end
  end

  context "items remaining" do
    test "deleted repo removes pin count from profile" do
      remaining = @user.pinned_items_remaining
      repo = create(:repository, owner: @user)
      pin = create(:profile_pin, pinned_item: repo, profile: @user_profile)
      assert_equal remaining - 1, @user.pinned_items_remaining

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob, DestroyDependentRecordsJob]) { repo.remove(@user) }
      assert_equal remaining, @user.pinned_items_remaining
    end
  end

  test "making the repository private deletes its profile pins" do
    owner = create(:user, plan: "medium")
    owner_profile = create(:profile, user: owner)
    repo = create(:repository, owner: owner)
    pin = create(:profile_pin, pinned_item: repo, profile: owner_profile)

    assert_difference("ProfilePin.count", -1) do
      perform_enqueued_hydro_jobs(only: [HydroProfilesRepositoryVisibilityJob]) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          repo.toggle_visibility(actor: repo.owner, visibility: "private")
        end
      end
    end

    refute ProfilePin.exists?(pin.id)
  end

  test "deletes pinned repository join records on destroy" do
    repo = create(:repository)
    pin = create(:profile_pin, pinned_item: repo)

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      RepositoryOrchestration.delete(repo, actor: User.ghost).execute(synchronous: true)
    end

    refute ProfilePin.exists?(pin.id)
  end
end
