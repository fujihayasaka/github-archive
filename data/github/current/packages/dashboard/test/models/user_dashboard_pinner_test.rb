# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDashboardPinnerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context ".unpin" do
    test "unpins a pinned repository for the given user" do
      repo = create(:repository, owner: @user)
      pin = create(:user_dashboard_pin, pinned_item: repo, user: @user)

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, repo.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(repo, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, repo.id
    end

    test "unpins a pinned gist for the given user" do
      gist = create(:gist, user: @user)
      pin = create(:user_dashboard_pin, pinned_item: gist, user: @user)

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, gist.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(gist, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, gist.id
    end

    test "unpins a pinned issue for the given user" do
      pin = create(:user_dashboard_pin, :issue, user: @user)
      issue = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, issue.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(issue, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, issue.id
    end

    test "unpins a pinned pull request for the given user" do
      pin = create(:user_dashboard_pin, :pull_request, user: @user)
      pull_request = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, pull_request.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(pull_request, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, pull_request.id
    end

    test "unpins a pinned project for the given user" do
      pin = create(:user_dashboard_pin, :project, user: @user)
      project = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, project.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(project, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, project.id
    end

    test "unpins a pinned user for the given user" do
      pin = create(:user_dashboard_pin, :user, user: @user)
      user = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, user.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(user, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, user.id
    end

    test "unpins a pinned organization for the given user" do
      pin = create(:user_dashboard_pin, :organization, user: @user)
      organization = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, organization.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(organization, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, organization.id
    end

    test "unpins a pinned team for the given user" do
      pin = create(:user_dashboard_pin, :team, user: @user)
      team = pin.pinned_item

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, team.id

      assert_difference("@user.dashboard_pins.count", -1) do
        UserDashboardPinner.unpin(team, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, team.id
    end

    test "unpins many items at once" do
      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      pin1 = create(:user_dashboard_pin, pinned_item: repo1, user: @user)
      pin2 = create(:user_dashboard_pin, pinned_item: repo2, user: @user)

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      assert_includes pinned_item_ids, repo1.id
      assert_includes pinned_item_ids, repo2.id

      assert_difference("@user.dashboard_pins.count", -2) do
        UserDashboardPinner.unpin(repo1, repo2, user: @user, viewer: @user)
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:pinned_item_id)
      refute_includes pinned_item_ids, repo1.id
      refute_includes pinned_item_ids, repo2.id
    end
  end

  context ".pin" do
    test "allows user to pin a repository to their dashboard" do
      repo = create(:repository, owner: @user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(repo, user: @user, viewer: @user)
      end
    end

    test "allows user to pin a gist to their dashboard" do
      gist = create(:gist, user: @user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(gist, user: @user, viewer: @user)
      end
    end

    test "allows user to pin an issue to their dashboard" do
      issue = create(:issue, user: @user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(issue, user: @user, viewer: @user)
      end
    end

    test "allows user to pin a pull request to their dashboard" do
      repo = create(:repository, owner: @user, from_example: :simple)
      pr = create(:pull_request, repository: repo, base_ref: "master",
        head_ref: "cr-line-endings", user: repo.owner)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(pr, user: @user, viewer: @user)
      end
    end

    test "allows user to pin a project to their dashboard" do
      project = create(:project, owner: @user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(project, user: @user, viewer: @user)
      end
    end

    test "allows user to pin a user to their dashboard" do
      user = create(:user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(user, user: @user, viewer: @user)
      end
    end

    test "allows user to pin an org to their dashboard" do
      org = create(:organization, admin: @user)

      assert_difference("@user.dashboard_pins.count") do
        UserDashboardPinner.pin(org, user: @user, viewer: @user)
      end
    end

    test "allows user to pin a team to their dashboard" do
      team = create(:team)
      team.add_member(@user)

      assert_difference("@user.dashboard_pins.count", 1) do
        UserDashboardPinner.pin(team, user: @user, viewer: @user)
      end
    end
  end
end
