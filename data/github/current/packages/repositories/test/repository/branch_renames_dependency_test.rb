# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBranchRenamesDependencyTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)

    @org_admin = create(:user)
    @org = create(:business_plus_organization, admin: @org_admin)
    @org_repo = create(:repository, owner: @org)

    # We once had an obscure bug where this call failed only on orgs with >1 admin
    @org_admin_2 = create(:user)
    @org.add_member(@org_admin_2, action: :admin, adder: @org_admin)

    @repo_triager = create(:user)
    @org_repo.add_member(@repo_triager, action: :triage)

    @repo_maintainer = create(:user)
    @org_repo.add_member(@repo_maintainer, action: :maintain)

    @repo_writer = create(:user)
    @org_repo.add_member(@repo_writer, action: :write)

    @repo_admin = create(:user)
    @org_repo.add_member(@repo_admin, action: :admin)

    # No explicit permission grants necessary to have read access since both
    # @repo and @org_repo are public
    @repo_reader = create(:user)
  end

  def create_bot(extra_permissions = {})
    permissions = { "metadata" => :read, "contents" => :write }.merge(extra_permissions)

    app = create(:integration, default_permissions: permissions)
    bot = create(:bot, integration: app)
    installation = make_integration_installation(
      target: @org,
      integration: app,
      repositories: nil, # all repos
      permissions: permissions
    )
    bot.installation = installation
    bot
  end

  context "#branch_renameable_by?" do
    test "true for repo owner and default branch" do
      assert @repo.branch_renameable_by?(@owner, branch: @repo.default_branch)
    end

    test "true for repo owner and non-default branch" do
      assert @repo.branch_renameable_by?(@owner, branch: "some-other-branch")
    end

    test "true for repo admin and default branch" do
      assert @org_repo.branch_renameable_by?(@repo_admin, branch: @org_repo.default_branch)
    end

    test "true for repo admin and non-default branch" do
      assert @org_repo.branch_renameable_by?(@repo_admin, branch: "some-other-branch")
    end

    test "false for repo maintainer and default branch" do
      refute @org_repo.branch_renameable_by?(@repo_maintainer, branch: @org_repo.default_branch)
    end

    test "true for repo maintainer and non-default branch" do
      assert @org_repo.branch_renameable_by?(@repo_maintainer, branch: "some-other-branch")
    end

    test "false for repo writer and default branch" do
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: @org_repo.default_branch)
    end

    test "true for repo writer and non-default branch" do
      assert @org_repo.branch_renameable_by?(@repo_writer, branch: "some-other-branch")
    end

    test "false for repo triager and default branch" do
      refute @org_repo.branch_renameable_by?(@repo_triager, branch: @org_repo.default_branch)
    end

    test "false for repo triager and non-default branch" do
      refute @org_repo.branch_renameable_by?(@repo_triager, branch: "some-other-branch")
    end

    test "false for repo reader and default branch" do
      refute @repo.branch_renameable_by?(@repo_reader, branch: @repo.default_branch)
    end

    test "false for repo reader and non-default branch" do
      refute @repo.branch_renameable_by?(@repo_reader, branch: "some-other-branch")
    end

    test "false for repo writer and non-default protected branch" do
      rule = create(:protected_branch, name: "some-other-branch", repository: @org_repo)
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: "some-other-branch")
    end

    test "true for repo admin and non-default protected branch" do
      rule = create(:protected_branch, name: "some-other-branch", repository: @org_repo)
      assert @org_repo.branch_renameable_by?(@repo_admin, branch: "some-other-branch")
    end

    test "true for org/repo admins and when push rules enabled" do
      @org_repo.private = true
      @org_repo.save!

      create(:repository_ruleset, :push_ruleset, :targets_all_repos, source: @org_repo.owner, target: :push)

      assert @org_repo.branch_renameable_by?(@org_admin, branch: @org_repo.default_branch)
      assert @org_repo.branch_renameable_by?(@org_admin, branch: "some-other-branch")
      assert @org_repo.branch_renameable_by?(@repo_admin, branch: @org_repo.default_branch)
      assert @org_repo.branch_renameable_by?(@repo_admin, branch: "some-other-branch")
    end

    test "only org admin can bypass org rule on default branch" do
      create(:repository_ruleset, :example_ruleset, :targets_all_repos, source: @org_repo.owner)

      assert @org_repo.branch_renameable_by?(@org_admin, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(@repo_admin, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: @org_repo.default_branch)

      org_admin_bot = create_bot({ "administration" => :write, "organization_administration" => :write })
      org_repo_admin_bot = create_bot({ "administration" => :write })
      org_repo_writer_bot = create_bot
      # These are needed after create_bot() adds apps and installations
      @org_repo.reload
      @org.reload

      assert @org_repo.branch_renameable_by?(org_admin_bot, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(org_repo_admin_bot, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(org_repo_writer_bot, branch: @org_repo.default_branch)
    end

    test "only org admin can bypass org rule on non-default branch" do
      ruleset = create(:repository_ruleset, :targets_all_branches, :targets_all_repos, source: @org_repo.owner)
      create(:repository_rule_configuration, repository_ruleset: ruleset)

      assert @org_repo.branch_renameable_by?(@org_admin, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(@repo_admin, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: "some-other-branch")

      org_admin_bot = create_bot({ "administration" => :write, "organization_administration" => :write })
      org_repo_admin_bot = create_bot({ "administration" => :write })
      org_repo_writer_bot = create_bot
      # These are needed after create_bot() adds apps and installations
      @org_repo.reload
      @org.reload

      assert @org_repo.branch_renameable_by?(org_admin_bot, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(org_repo_admin_bot, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(org_repo_writer_bot, branch: "some-other-branch")
    end

    test "only org/repo admins can bypass repo rule on default branch" do
      create(:repository_ruleset, :example_ruleset, source: @org_repo)

      assert @org_repo.branch_renameable_by?(@repo_admin, branch: @org_repo.default_branch)
      assert @org_repo.branch_renameable_by?(@org_admin, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: @org_repo.default_branch)

      org_admin_bot = create_bot({ "administration" => :write, "organization_administration" => :write })
      org_repo_admin_bot = create_bot({ "administration" => :write })
      org_repo_writer_bot = create_bot
      # These are needed after create_bot() adds apps and installations
      @org_repo.reload
      @org.reload

      assert @org_repo.branch_renameable_by?(org_admin_bot, branch: @org_repo.default_branch)
      assert @org_repo.branch_renameable_by?(org_repo_admin_bot, branch: @org_repo.default_branch)
      refute @org_repo.branch_renameable_by?(org_repo_writer_bot, branch: @org_repo.default_branch)
    end

    test "only org/repo admins can bypass repo rule on non-default branch" do
      ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
      create(:repository_rule_configuration, repository_ruleset: ruleset)

      assert @org_repo.branch_renameable_by?(@repo_admin, branch: "some-other-branch")
      assert @org_repo.branch_renameable_by?(@org_admin, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(@repo_writer, branch: "some-other-branch")

      org_admin_bot = create_bot({ "administration" => :write, "organization_administration" => :write })
      org_repo_admin_bot = create_bot({ "administration" => :write })
      org_repo_writer_bot = create_bot
      # These are needed after create_bot() adds apps and installations
      @org_repo.reload
      @org.reload

      assert @org_repo.branch_renameable_by?(org_admin_bot, branch: "some-other-branch")
      assert @org_repo.branch_renameable_by?(org_repo_admin_bot, branch: "some-other-branch")
      refute @org_repo.branch_renameable_by?(org_repo_writer_bot, branch: "some-other-branch")
    end
  end

  context "#branch_recently_renamed?" do
    test "true when given branch was renamed recently" do
      rename = create(:repository_branch_rename, :finished, repository: @repo)
      assert @repo.branch_recently_renamed?(rename.new_name)
    end

    test "false when given branch has never been renamed" do
      refute @repo.branch_recently_renamed?("master")
    end

    test "false when given branch was renamed but not recently" do
      rename = travel_to(3.weeks.ago) do
        create(:repository_branch_rename, :finished, repository: @repo)
      end
      refute @repo.branch_recently_renamed?(rename.new_name)
    end
  end

  context "#branches_being_renamed" do
    test "includes old branch names that are in the process of being renamed" do
      example_repo :simple, @repo
      create(:repository_branch_rename, repository: @repo, old_name: "master")
      assert_equal ["master"], @repo.branches_being_renamed
    end

    test "empty when no branches have been renamed" do
      assert_empty @repo.branches_being_renamed
    end

    test "does not include finished and errored renames" do
      errored_rename = create(:repository_branch_rename, state: :errored, repository: @repo)
      finished_rename = create(:repository_branch_rename, state: :finished, repository: @repo)

      result = @repo.branches_being_renamed

      refute_includes result, errored_rename.old_name
      refute_includes result, finished_rename.old_name
    end
  end

  context "#branch_being_renamed?" do
    test "true when rename has been started for specified branch" do
      example_repo :simple, @repo
      create(:repository_branch_rename, repository: @repo, old_name: "master")
      assert @repo.branch_being_renamed?("master")
    end

    test "false when rename for another branch has been started" do
      example_repo :simple, @repo
      create(:repository_branch_rename, repository: @repo, old_name: "cr-line-endings")
      refute @repo.branch_being_renamed?("master")
    end

    test "false when no branch rename has been started" do
      refute @repo.branch_being_renamed?("master")
    end

    test "false when rename finished in an error state" do
      create(:repository_branch_rename, state: :errored, repository: @repo,
        old_name: "master")
      refute @repo.branch_being_renamed?("master")
    end

    test "false when rename finished successfully" do
      create(:repository_branch_rename, state: :finished, repository: @repo,
        old_name: "master")
      refute @repo.branch_being_renamed?("master")
    end
  end

  context "#branch_rename_for" do
    test "returns nil when no renames exist for that branch" do
      assert_nil @repo.branch_rename_for(old_name: "some-branch")
    end

    test "returns finished rename when it exists" do
      rename = create(:repository_branch_rename, :finished, repository: @repo)
      assert_equal rename, @repo.branch_rename_for(old_name: rename.old_name)
    end

    test "allows lookup by the new name" do
      rename = create(:repository_branch_rename, :finished, repository: @repo)
      assert_equal rename, @repo.branch_rename_for(new_name: rename.new_name)
    end

    test "returns most recent rename when the same branch has existed and been renamed multiple times" do
      rename1 = create(:repository_branch_rename, :finished, repository: @repo,
        old_name: "pickles", new_name: "cucumbers")
      rename2 = create(:repository_branch_rename, :finished, repository: @repo,
        old_name: "cucumbers", new_name: "pickles")
      rename3 = create(:repository_branch_rename, :finished, repository: @repo,
        old_name: "pickles", new_name: "tomatoes")

      assert_equal rename3, @repo.branch_rename_for(old_name: "pickles")
    end

    test "does not return errored rename" do
      rename = create(:repository_branch_rename, :errored, repository: @repo)
      assert_nil @repo.branch_rename_for(old_name: rename.old_name)
    end

    test "does not return rename that is still in progress" do
      example_repo :mojombo_grit, @repo
      rename = create(:repository_branch_rename, repository: @repo,
        old_name: "diverge", new_name: "converge")
      assert_nil @repo.branch_rename_for(old_name: rename.old_name)
    end
  end
end
