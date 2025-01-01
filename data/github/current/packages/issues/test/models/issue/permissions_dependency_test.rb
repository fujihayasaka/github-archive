# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuePermissionsDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @owner = create(:user)
    @user = create(:user)
    @user_repo = create(:repository, owner: @owner)
    @user_repo_issue = create(:issue,
      repository: @user_repo,
      user: @owner,
      title: "test",
    )

    @org = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @org)
    @org_repo_issue = create(:issue, repository: @org_repo)
    @org_team = create(:team, organization: @org, privacy: :closed)
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  context "#can_set_milestone?" do
    test "returns false for rando" do
      rando = create :user
      refute @user_repo_issue.can_set_milestone?(rando)
    end

    test "returns true for repository owner" do
      assert @user_repo_issue.can_set_milestone?(@owner)
    end

    test "returns false contributor with read permissions" do
      collaborator_with_read = create :user
      @user_repo.add_member(collaborator_with_read, action: :read)
      refute @user_repo_issue.can_set_milestone?(collaborator_with_read)
    end

    test "returns true contributor with write permissions" do
      collaborator_with_write = create :user
      @user_repo.add_member(collaborator_with_write, action: :write)
      assert @user_repo_issue.can_set_milestone?(collaborator_with_write)
    end

    test "returns false for user with read access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :read)
      refute @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns true for user with triage access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :triage)
      assert @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns true for user with write access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :write)
      assert @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns true for user with maintain access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :maintain)
      assert @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns true for user with admin access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :admin)
      assert @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns false for a member of team with read on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :pull
      refute @org_repo_issue.can_set_milestone?(team_member)
    end

    test "returns true for a member of team with triage on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :triage
      assert @org_repo_issue.can_set_milestone?(team_member)
    end

    test "returns true for a member of nested team with triage on org owned repo" do
      team_member = create :user
      nested_team = create(:team, organization: @org, parent_team_id: @org_team.id, privacy: :closed)
      nested_team.add_member(team_member)
      nested_team.add_repository @org_repo, :triage
      assert @org_repo_issue.can_set_milestone?(team_member)
    end

    test "returns true for a member of team with write on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :push
      assert @org_repo_issue.can_set_milestone?(team_member)
    end

    test "returns true for a member of team with admin on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :admin
      assert @org_repo_issue.can_set_milestone?(team_member)
    end

    test "returns false if the repository is archived" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :triage)
      @org_repo.set_archived
      assert @org_repo.archived?
      refute @org_repo_issue.can_set_milestone?(org_member)
    end

    test "returns true if a staff user has a repository unlock" do
      unlocker = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      grant = create :staff_access_grant, accessible: @org_repo_issue.repository, granted_by: @owner
      assert unlocker.unlock_repository(@org_repo_issue.repository)
      assert @org_repo_issue.can_set_milestone?(unlocker)
    end

    test "returns false if a staff user has NO a repository unlock" do
      unlocker = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      refute @org_repo_issue.can_set_milestone?(unlocker)
    end

    test "returns false when no user is provided" do
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).never
      refute @org_repo_issue.can_set_milestone?(nil)
    end
  end

  context "#can_mark_as_duplicate?" do
    test "returns false when no user is provided" do
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).never
      refute @user_repo_issue.can_mark_as_duplicate?(nil)
    end

    test "returns false for rando" do
      rando = create :user
      refute @user_repo_issue.can_mark_as_duplicate?(rando)
    end

    test "returns true for repository owner" do
      assert @user_repo_issue.can_mark_as_duplicate?(@owner)
    end

    test "returns false contributor with read permissions" do
      collaborator_with_read = create :user
      @user_repo.add_member(collaborator_with_read, action: :read)
      refute @user_repo_issue.can_mark_as_duplicate?(collaborator_with_read)
    end

    test "returns true contributor with write permissions" do
      collaborator_with_write = create :user
      @user_repo.add_member(collaborator_with_write, action: :write)
      assert @user_repo_issue.can_mark_as_duplicate?(collaborator_with_write)
    end

    test "returns false for user with read access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :read)
      refute @org_repo_issue.can_mark_as_duplicate?(org_member)
    end

    test "returns true for user with triage access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :triage)
      assert @org_repo_issue.can_mark_as_duplicate?(org_member)
    end

    test "returns true for user with write access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :write)
      assert @org_repo_issue.can_mark_as_duplicate?(org_member)
    end

    test "returns true for user with maintain access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :maintain)
      assert @org_repo_issue.can_mark_as_duplicate?(org_member)
    end

    test "returns true for user with admin access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :admin)
      assert @org_repo_issue.can_mark_as_duplicate?(org_member)
    end

    test "returns false for a member of team with read on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :pull
      refute @org_repo_issue.can_mark_as_duplicate?(team_member)
    end

    test "returns true for a member of team with triage on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :triage
      assert @org_repo_issue.can_mark_as_duplicate?(team_member)
    end

    test "returns true for a member of nested team with triage on org owned repo" do
      team_member = create :user
      nested_team = create(:team, organization: @org, parent_team_id: @org_team.id, privacy: :closed)
      nested_team.add_member(team_member)
      nested_team.add_repository @org_repo, :triage
      assert @org_repo_issue.can_mark_as_duplicate?(team_member)
    end

    test "returns true for a member of team with write on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :push
      assert @org_repo_issue.can_mark_as_duplicate?(team_member)
    end

    test "returns true for a member of team with admin on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :admin
      assert @org_repo_issue.can_mark_as_duplicate?(team_member)
    end

    test "returns true if a staff user has a repository unlock" do
      unlocker = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      grant = create :staff_access_grant, accessible: @org_repo_issue.repository, granted_by: @owner
      assert unlocker.unlock_repository(@org_repo_issue.repository)
      assert @org_repo_issue.can_mark_as_duplicate?(unlocker)
    end

    test "returns false if a staff user has NO a repository unlock" do
      unlocker = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      refute @org_repo_issue.can_mark_as_duplicate?(unlocker)
    end
  end

  context "#labelable_by?" do
    test "true if user is owner of repository" do
      issue = create(:issue, repository: @user_repo)
      assert @user_repo.pushable_by?(@owner)

      assert issue.labelable_by?(actor: @owner)
    end

    test "true if user can write to repository" do
      issue = create(:issue, repository: @user_repo)
      @user_repo.add_member(@user)
      assert @user_repo.pushable_by?(@user)

      assert issue.labelable_by?(actor: @user)
    end

    test "true if user can admin repository" do
      issue = create(:issue, repository: @user_repo)
      assert @user_repo.adminable_by?(@owner)

      assert issue.labelable_by?(actor: @owner)
    end

    test "true if a user has been granted triage" do
      @org_repo.send(:grant, @user, :triage)
      issue = create(:issue, repository: @org_repo)

      assert issue.labelable_by?(actor: @user)
    end

    test "true if a user has been granted fgps add_label" do
      custom_role = create_custom_role(role_name: "foo_label", owner: @org, fgps: ["add_label"])
      user_with_custom_role = create(:user)
      @org_repo.add_member(user_with_custom_role, action: custom_role.name)
      issue = create(:issue, repository: @org_repo)

      assert issue.labelable_by?(actor: user_with_custom_role)
    end

    test "true for issue with pull request" do
      pull_request = create(:pull_request, :disable_disk_access, repository: @user_repo)
      @user_repo.add_member(@user)
      assert @user_repo.pushable_by?(@user)

      assert pull_request.issue.labelable_by?(actor: @user)
    end

    test "false if user can only read repository" do
      issue = create(:issue, repository: @user_repo)
      refute @user_repo.pushable_by?(@user)

      refute issue.labelable_by?(actor: @user)
    end

    test "true for installation installed on all repos" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "pull_requests" => :write
        }
      )
      pull_request = create(:pull_request, :disable_disk_access, repository: repo_with_installation)
      assert pull_request.labelable_by?(actor: installation.bot)
    end

    test "false for installation not installed for repo target" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      random_user = create(:user)
      random_user_repo = create :repository, owner: random_user

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "pull_requests" => :write
        }
      )
      pull_request = create(:pull_request, :disable_disk_access, repository: random_user_repo)
      refute pull_request.labelable_by?(actor: installation.bot)
    end

    test "returns false when no user is provided" do
      issue = create(:issue, repository: @user_repo)
      issue.expects(:async_pull_request).never
      refute issue.labelable_by?(actor: nil)
    end
  end

  context "#assignable_by?" do
    test "true if user can write to repository" do
      issue = create(:issue, repository: @user_repo)
      @user_repo.add_member(@user)
      assert @user_repo.pushable_by?(@user)

      assert issue.assignable_by?(actor: @user)
    end

    test "true if user can admin repository" do
      issue = create(:issue, repository: @user_repo)
      assert @user_repo.adminable_by?(@owner)

      assert issue.assignable_by?(actor: @owner)
    end

    test "true if a user has been granted triage" do
      @org_repo.send(:grant, @user, :triage)
      issue = create(:issue, repository: @org_repo)

      assert issue.assignable_by?(actor: @user)
    end

    test "true for issue with pull request" do
      pull_request = create(:pull_request, :disable_disk_access, repository: @user_repo)
      @user_repo.add_member(@user)
      assert @user_repo.pushable_by?(@user)

      assert pull_request.issue.assignable_by?(actor: @user)
    end

    test "false if user can only read repository" do
      issue = create(:issue, repository: @user_repo)
      refute @user_repo.pushable_by?(@user)

      refute issue.assignable_by?(actor: @user)
    end

    test "returns false when no user is provided" do
      issue = create(:issue, repository: @user_repo)
      issue.expects(:async_pull_request).never
      refute issue.assignable_by?(actor: nil)
    end
  end

  context "#deleteable_by?" do
    test "true for installation installed on all repos" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "issues" => :write,
          "administration" => :write
        }
      )
      issue = create(:issue, repository: repo_with_installation)
      assert issue.deleteable_by?(installation.bot)
    end

    test "false for installation not installed for repo target" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      random_user = create(:user)
      random_user_repo = create :repository, owner: random_user

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "issues" => :write,
          "administration" => :write
        }
      )
      issue = create(:issue, repository: random_user_repo)
      refute issue.deleteable_by?(installation.bot)
    end

    test "requires issues:write AND administation:write" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      admin_installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "administration" => :write
        }
      )
      issue_installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "issues" => :write
        }
      )
      issue = create(:issue, repository: repo_with_installation)
      refute issue.deleteable_by?(admin_installation.bot)
      refute issue.deleteable_by?(issue_installation.bot)
    end
  end

  context "#triageable_by?" do
    test "returns truthy if the user has a triage role" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      triage_user = create(:user)
      org_repo.add_member(triage_user, action: :triage)

      assert issue.triageable_by?(triage_user)
    end

    test "returns truthy if the user has :write, :maintain, or :admin role" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      [:write, :maintain, :admin].each do |role|
        user = create(:user)
        org_repo.add_member(user, action: role)

        assert issue.triageable_by?(user)
      end
    end

    test "returns falsey if the user has read only access" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      triage_user = create(:user)
      org_repo.add_member(triage_user, action: :read)

      refute issue.triageable_by?(triage_user)
    end

    test "returns falsey if the user can't push to the repository" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:private_repository, owner: org)
      issue = create(:issue, repository: org_repo)

      unauthorize_user = create(:user)

      refute issue.triageable_by?(unauthorize_user)
    end

    test "returns falsey if the user does not have access to a fork" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)

      user = create(:user)
      fork_repo = create(:fork_repository, forker: user, fork_repo: org_repo)

      issue = create(:issue, repository: fork_repo)

      refute issue.triageable_by?(org_admin)
    end

    test "returns truthy if the team has a triage role" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)

      issue = create(:issue, repository: org_repo)
      team = create(:public_team, organization: org)

      org_repo.add_team(team, action: :triage)

      assert issue.triageable_by?(team)
    end

    test "returns truthy if the team has :write, :maintain, or :admin role" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      [:write, :maintain, :admin].each do |role|
        team = create(:public_team, organization: org)
        org_repo.add_team(team, action: role)

        assert issue.triageable_by?(team)
      end
    end

    test "returns falsey if the team has read only access" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)

      issue = create(:issue, repository: org_repo)
      team = create(:public_team, organization: org)

      org_repo.add_team(team, action: :read)
      refute issue.triageable_by?(team)
    end

    test "rejects bots as users with triage access" do
      org_admin = create(:user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      triage_bot = create(:integration).bot
      org_repo.add_member(triage_bot, action: :triage)

      refute issue.triageable_by?(triage_bot)
    end
  end
end
