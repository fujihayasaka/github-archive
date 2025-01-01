# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTemplateInitializerTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
  end

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

  test "generates README.md file" do
    @repo.auto_init = true

    Repository::TemplateInitializer.new(@repo).perform

    readme = read_file("README.md")
    assert_includes readme, "a-brand-new-repo"
    assert_includes readme, "hello world!"
  end

  test "generates LICENSE file" do
    @repo.license_template = "MIT"

    Repository::TemplateInitializer.new(@repo).perform

    license = read_file("LICENSE")
    assert_includes license, "MIT License"
    assert_includes license, @repo.owner.name
  end

  test "generates .gitignore file" do
    @repo.gitignore_template = "Ruby"

    Repository::TemplateInitializer.new(@repo).perform

    gitignore = read_file(".gitignore")
    assert_equal File.read("#{Rails.root}/vendor/gitignore/Ruby.gitignore"), gitignore
  end

  context "branch names" do
    test "uses owner's default branch config when auto initializing repo" do
      @repo.auto_init = true
      @repo.owner.set_default_new_repo_branch("starter-branch", actor: @repo.owner)

      Repository::TemplateInitializer.new(@repo).perform

      assert_equal "starter-branch", @repo.default_branch
      branch = @repo.heads.find("starter-branch")
      refute_nil branch
    end

    test "uses owner's default branch config when not auto initializing repo" do
      @repo.auto_init = false
      @repo.owner.set_default_new_repo_branch("starter-branch", actor: @repo.owner)

      Repository::TemplateInitializer.new(@repo).perform

      assert_equal "starter-branch", @repo.default_branch
    end

    test "uses owner's default branch config when auto initializing org repo" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      org.set_default_new_repo_branch("starter-branch", actor: org_admin)
      org_repo = create(:repository, owner: org, created_by_user_id: org_admin.id)
      org_repo.auto_init = true

      Repository::TemplateInitializer.new(org_repo).perform

      assert_equal "starter-branch", org_repo.default_branch
      branch = org_repo.heads.find("starter-branch")
      refute_nil branch
    end

    test "uses owner's default branch config when not auto initializing org repo" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      org.set_default_new_repo_branch("starter-branch", actor: org_admin)
      org_repo = create(:repository, owner: org, created_by_user_id: org_admin.id)
      org_repo.auto_init = false

      Repository::TemplateInitializer.new(org_repo).perform

      assert_equal "starter-branch", org_repo.default_branch
    end

    test "uses fallback if owner is missing" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, created_by_user_id: @repo.owner_id)
      org_repo.auto_init = true
      org.delete

      Repository::TemplateInitializer.new(org_repo).perform
      org_repo.reload

      assert_equal Configurable::DefaultNewRepoBranch.recommended_name, org_repo.default_branch
      branch = org_repo.heads.find(org_repo.default_branch)
      refute_nil branch
    end
  end

  context "commit signing" do
    test "signs commit" do
      @private.auto_init = true

      Repository::TemplateInitializer.new(@private).perform

      commit_oid = @private.heads.find(@private.default_branch).target_oid
      commit = @private.commits.find(commit_oid)

      assert_predicate commit, :verified_signature?
    end

    test "commit signing error handling" do
      GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)
      @private.auto_init = true

      Repository::TemplateInitializer.new(@private).perform

      commit_oid = @private.default_oid
      commit = @private.commits.find(commit_oid)

      refute_predicate commit, :has_signature?
    end
  end if GitHub.web_commit_signing_enabled?
end
