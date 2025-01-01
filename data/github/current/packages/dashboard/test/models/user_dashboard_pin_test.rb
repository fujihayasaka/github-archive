# typed: false
# frozen_string_literal: true

require "test_helper"

class UserDashboardPinTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "Hydro events" do
    test "logs event on creation for a repo pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "REPOSITORY",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for a gist pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :gist, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "GIST",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for an issue pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :issue, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "ISSUE",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for a pull request pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :pull_request, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "PULL_REQUEST",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for a project pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :project, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "PROJECT",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for a user pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :user, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "USER",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for an organization pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :organization, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "ORGANIZATION",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on creation for a team pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :team, user: @user)
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "TEAM",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs event on deletion for a repo pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "REPOSITORY",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for a gist pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :gist, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "GIST",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for an issue pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :issue, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "ISSUE",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for a pull request pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :pull_request, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "PULL_REQUEST",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for a project pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :project, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "PROJECT",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for a user pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :user, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "USER",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for an organization pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :organization, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "ORGANIZATION",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end

    test "logs event on deletion for a team pin from a user", skip_enterprise: true do
      pin = create(:user_dashboard_pin, :team, user: @user)
      pin.destroy
      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: pin.position,
        pinned_item_id: pin.pinned_item_id,
        pinned_item_type: "TEAM",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinDestroy")
    end
  end

  context "validations" do
    test "requires a pinned_item_type" do
      user_dashboard_pin = UserDashboardPin.new
      refute_predicate user_dashboard_pin, :valid?
      assert_includes user_dashboard_pin.errors[:pinned_item_type], "can't be blank"
    end

    test "requires a pinned_item_id" do
      user_dashboard_pin = UserDashboardPin.new
      refute_predicate user_dashboard_pin, :valid?
      assert_includes user_dashboard_pin.errors[:pinned_item_id], "can't be blank"
    end

    test "allows 25 pins per dashboard" do
      user = create(:user)
      last_user_dashboard_pin = nil
      25.times do
        last_user_dashboard_pin = create(:user_dashboard_pin, user: user)
      end
      user_dashboard_pin = build(:user_dashboard_pin, user: user)
      refute user_dashboard_pin.valid?, "twenty-sixth pin should not be valid"
      assert_includes user_dashboard_pin.errors.full_messages,
        "Total pins for your dashboard cannot exceed 25"
    end

    test "requires a unique item per user" do
      gist = create(:gist)
      create(:user_dashboard_pin, pinned_item: gist, user: gist.user)

      user_dashboard_pin = build(:user_dashboard_pin, pinned_item: gist, user: gist.user, position: 2)

      refute_predicate user_dashboard_pin, :valid?
      assert_includes user_dashboard_pin.errors[:pinned_item_id], "has already been taken"
    end

    test "allows pinning a private repository" do
      private_repo = create(:private_repository)
      pin = build(:user_dashboard_pin, pinned_item: private_repo)
      assert_predicate pin, :valid?
    end

    test "allows pinning a secret gist" do
      secret_gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: @user,
                                  public: false)
      pin = build(:user_dashboard_pin, pinned_item: secret_gist)
      assert_predicate pin, :valid?
    end

    test "disallows pinning an inactive repository" do
      inactive_repo = create(:repository, active: nil)
      pin = build(:user_dashboard_pin, pinned_item: inactive_repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must be active"
    end

    test "disallows pinning a disabled repository" do
      repo = create(:repository, disabled_at: 1.week.ago)
      pin = build(:user_dashboard_pin, pinned_item: repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a disabled gist" do
      gist = create(:gist, disabled_at: 1.week.ago)
      pin = build(:user_dashboard_pin, pinned_item: gist)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a repository with a disabled access reason" do
      repo = create(:repository, disabled_at: Time.now, disabling_reason: "size")
      pin = build(:user_dashboard_pin, pinned_item: repo)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end

    test "disallows pinning a gist with a disabled access reason" do
      gist = create(:gist, disabled_at: Time.now, disabling_reason: "size")
      pin = build(:user_dashboard_pin, pinned_item: gist)
      refute_predicate pin, :valid?
      assert_includes pin.errors[:pinned_item], "must not be disabled"
    end
  end

  context "pinned_by_user scope" do
    test "includes only pins for the given user" do
      user1 = create(:user)
      user2 = create(:user)
      user1_pin1 = create(:user_dashboard_pin, user: user1)
      user2_pin1 = create(:user_dashboard_pin, user: user2)
      user1_pin2 = create(:user_dashboard_pin, :gist, user: user1, position: 2)
      user2_pin2 = create(:user_dashboard_pin, :gist, user: user2, position: 2)

      result = UserDashboardPin.pinned_by_user(user2)

      assert_includes result, user2_pin1
      assert_includes result, user2_pin2
      refute_includes result, user1_pin1
      refute_includes result, user1_pin2
    end
  end

  context "for_item scope" do
    test "includes only pins with the given item type and item id" do
      user1 = create(:user)
      user2 = create(:user)
      issue1 = create(:issue)
      issue2 = create(:issue)
      gist = create(:gist)
      user1_pin1 = create(:user_dashboard_pin, user: user1, pinned_item: issue1)
      user2_pin1 = create(:user_dashboard_pin, user: user2, pinned_item: issue1)
      user1_pin2 = create(:user_dashboard_pin, user: user1, pinned_item: issue2)
      user1_pin3 = create(:user_dashboard_pin, user: user1, pinned_item: gist)

      result = UserDashboardPin.for_item(issue1.id, issue1.class.name)

      assert_includes result, user1_pin1
      assert_includes result, user2_pin1
      refute_includes result, user1_pin2
      refute_includes result, user1_pin3
    end
  end

  context "ordered_by_position scope" do
    test "returns the pins in ascending order by position" do
      user = create(:user)
      user_dashboard_pin1 = create(:user_dashboard_pin, user: user, position: 2)
      user_dashboard_pin2 = create(:user_dashboard_pin, user: user, position: 1)
      user_dashboard_pin3 = create(:user_dashboard_pin, user: user, position: 3)

      assert_equal [user_dashboard_pin2, user_dashboard_pin1, user_dashboard_pin3],
        UserDashboardPin.pinned_by_user(user).ordered_by_position
    end
  end

  context "#pinned_item=" do
    test "sets pinned_item_type and pinned_item_id for the given repo" do
      repo = create(:repository, owner: @user)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = repo

      assert_equal repo.id, user_dashboard_pin.pinned_item_id
      assert_equal "Repository", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given gist" do
      gist = create(:gist)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = gist

      assert_equal gist.id, user_dashboard_pin.pinned_item_id
      assert_equal "Gist", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given issue" do
      issue = create(:issue)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = issue

      assert_equal issue.id, user_dashboard_pin.pinned_item_id
      assert_equal "Issue", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given project" do
      project = create(:project)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = project

      assert_equal project.id, user_dashboard_pin.pinned_item_id
      assert_equal "Project", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given pull_request" do
      repo = create(:repository, owner: @user, from_example: :simple)
      pull_request = create(:pull_request, repository: repo, base_ref: "master",
        head_ref: "cr-line-endings", user: repo.owner)

      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = pull_request

      assert_equal pull_request.id, user_dashboard_pin.pinned_item_id
      assert_equal "PullRequest", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given user" do
      user = create(:user)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = user

      assert_equal user.id, user_dashboard_pin.pinned_item_id
      assert_equal "User", user_dashboard_pin.pinned_item_type
    end

    test "sets pinned_item_type and pinned_item_id for the given team" do
      team = create(:team)
      user_dashboard_pin = UserDashboardPin.new

      user_dashboard_pin.pinned_item = team

      assert_equal team.id, user_dashboard_pin.pinned_item_id
      assert_equal "Team", user_dashboard_pin.pinned_item_type
    end
  end

  context "#pinned_item" do
    test "returns the repository when pinned_item_type is Repository" do
      repo = create(:repository, owner: @user)
      pin = UserDashboardPin.create!(pinned_item_type: "Repository", pinned_item_id: repo.id,
                               user_id: @user.id)
      assert_equal repo, pin.pinned_item
    end

    test "returns the gist when pinned_item_type is Gist" do
      gist = create(:gist, user: @user)
      pin = UserDashboardPin.create!(pinned_item_type: "Gist", pinned_item_id: gist.id,
                               user_id: @user.id)
      assert_equal gist, pin.pinned_item
    end

    test "get's destroyed in background with repository" do
      repo = create(:public_repository)
      other_repo = create(:public_repository)
      pin = UserDashboardPin.create!(pinned_item_type: "Repository", pinned_item_id: repo.id, user_id: @user.id)
      other_pin = UserDashboardPin.create!(pinned_item_type: "Repository", pinned_item_id: other_repo.id, user_id: @user.id)

      assert_destroyed_in_background_with_parent do |config|
        config.parent_record = repo
        config.expect_destroyed = [pin]
        config.expect_not_destroyed = [other_pin]
      end
    end
  end

  context "#repository?" do
    test "true for repo pin" do
      pin = create(:user_dashboard_pin)
      assert_predicate pin, :repository?
    end

    test "false for non repo pin" do
      pin = create(:user_dashboard_pin, :gist)
      refute_predicate pin, :repository?
    end
  end

  context "#gist?" do
    test "true for gist pin" do
      pin = create(:user_dashboard_pin, :gist)
      assert_predicate pin, :gist?
    end

    test "false for non gist pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :gist?
    end
  end

  context "#issue?" do
    test "true for issue pin" do
      pin = create(:user_dashboard_pin, :issue)
      assert_predicate pin, :issue?
    end

    test "false for non issue pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :issue?
    end
  end

  context "#pull_request?" do
    test "true for pull request pin" do
      pin = create(:user_dashboard_pin, :pull_request)
      assert_predicate pin, :pull_request?
    end

    test "false for non pull request pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :pull_request?
    end
  end

  context "#project?" do
    test "true for project pin" do
      pin = create(:user_dashboard_pin, :project)
      assert_predicate pin, :project?
    end

    test "false for non project pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :project?
    end
  end

  context "#user?" do
    test "true for user pin" do
      pin = create(:user_dashboard_pin, :user)
      assert_predicate pin, :user?
    end

    test "false for non user pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :user?
    end
  end

  context "#organization?" do
    test "true for organization pin" do
      pin = create(:user_dashboard_pin, :organization)
      assert_predicate pin, :organization?
    end

    test "false for non organization pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :organization?
    end
  end

  context "#team?" do
    test "true for team pin" do
      pin = create(:user_dashboard_pin, :team)
      assert_predicate pin, :team?
    end

    test "false for non team pin" do
      pin = create(:user_dashboard_pin)
      refute_predicate pin, :team?
    end
  end
end
