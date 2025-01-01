# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::InitializeRepositoryTest < GitHub::TestCase
  setup do
    @repo = create(:repository, name: "a-brand-new-repo", description: "hello world!")
    @repo.created_by_user_id = @repo.owner_id
    @repo.save

    @private = create(:private_repository, name: "a-brand-new-private-repo", description: "hello world!")
    @private.created_by_user_id = @private.owner_id
    @private.save

    WebFlowHelper.setup_webflow
  end

  def read_file(path)
    commit_oid = @repo.default_oid
    @repo.blob(commit_oid, path).data
  end

  test "generates README.md file", skip_enterprise: true do
    assert Codespaces::InitializeRepository.call(repository: @repo, actor: @repo.created_by)

    readme = read_file("README.md")
    assert_includes readme, "a-brand-new-repo"
    assert_includes readme, "hello world!"
  end

  context "pushable by", skip_enterprise: true do
    test "it requires the repository to be pushable by the actor" do
      refute Codespaces::InitializeRepository.call(repository: @repo, actor: create(:user))
    end
  end

  context "repository branch rules", skip_enterprise: true do
    test "it returns false if the repo init violates the repo's branch rules" do
      user = create(:user)
      org = create(:business_plus_organization)
      org.add_member user, action: :admin
      repo = create(:repository, owner: org)

      # Create a branch ruleset that will raise
      no_bypass_ruleset = create(
        :repository_ruleset,
        :targets_all_branches,
        source: repo
      )

      create(
        :repository_rule_configuration,
        :required_status_checks,
        repository_ruleset: no_bypass_ruleset,
      )

      refute Codespaces::InitializeRepository.call(repository: repo, actor: user)
    end
  end

  context "branch names", skip_enterprise: true do
    test "uses owner's default branch config when auto initializing repo" do
      @repo.owner.set_default_new_repo_branch("starter-branch", actor: @repo.owner)

      assert Codespaces::InitializeRepository.call(repository: @repo, actor: @repo.created_by)

      assert_equal "starter-branch", @repo.default_branch
      branch = @repo.heads.find("starter-branch")
      refute_nil branch
    end

    test "uses owner's default branch config when auto initializing org repo" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      org.set_default_new_repo_branch("starter-branch", actor: org_admin)
      org_repo = create(:repository, owner: org, created_by_user_id: org_admin.id)
      org_repo.auto_init = true

      assert Codespaces::InitializeRepository.call(repository: org_repo, actor: org_repo.created_by)

      assert_equal "starter-branch", org_repo.default_branch
      branch = org_repo.heads.find("starter-branch")
      refute_nil branch
    end

    test "uses fallback if owner is missing" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, created_by_user_id: @repo.owner_id)
      org_repo.add_member(@repo.owner)
      org.delete

      assert Codespaces::InitializeRepository.call(repository: org_repo, actor: @repo.owner)
      org_repo.reload

      assert_equal Configurable::DefaultNewRepoBranch.recommended_name, org_repo.default_branch
      branch = org_repo.heads.find(org_repo.default_branch)
      refute_nil branch
    end
  end

  context "commit signing", skip_enterprise: true do
    test "signs commit" do
      assert Codespaces::InitializeRepository.call(repository: @private, actor: @private.created_by)

      commit_oid = @private.heads.find(@private.default_branch).target_oid
      commit = @private.commits.find(commit_oid)

      assert_predicate commit, :verified_signature?
    end

    test "commit signing error handling" do
      GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)
      @private.auto_init = true

      assert Codespaces::InitializeRepository.call(repository: @private, actor: @private.created_by)

      commit_oid = @private.default_oid
      commit = @private.commits.find(commit_oid)

      refute_predicate commit, :has_signature?
    end
  end if GitHub.web_commit_signing_enabled?
end
