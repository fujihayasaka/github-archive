# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryLicenseTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create :user, login: "user", plan: "medium"

    @licensed_repo = create :repository, name: "licensed-repo", owner: @user, created_by_user_id: @user.id, from_example: :license_markdown
    @licensed_repo.license_template = "mit"
    @licensed_repo.initialize_git_repository_templates

    @private_repo = create :private_repository, name: "private-repo", owner: @user, created_by_user_id: @user.id, from_example: :license_markdown
    @private_repo.license_template = "mit"
    @private_repo.initialize_git_repository_templates

    @unlicensed_repo = create :repository, name: "unlicensed-repo", owner: @user, from_example: :license_none

    @copyrighted_repo = create :repository, name: "copyrighted-repo", owner: @user, from_example: :copyrighted_repo

    @other_license = create :repository, name: "other-license", owner: @user, from_example: :other_license

    @three_licenses = create :repository, name: "three-license", owner: @user, from_example: :three_licenses

    @duplicate_licenses = create :repository, name: "duplicate-licenses", owner: @user, from_example: :duplicate_license

    @invalid_licenses = create :repository, name: "invalid-licenses", owner: @user, from_example: :invalid_licenses
  end

  context "multiple licenses" do
    test "when unlicensed, does nothing" do
      RepositoryLicense.set_licenses(@unlicensed_repo)
      @unlicensed_repo.reload
      refute @unlicensed_repo.repository_license
    end

    test "when one license, sets the project license" do
      assert_empty @licensed_repo.repository_licenses
      RepositoryLicense.set_licenses(@licensed_repo)
      @licensed_repo.reload
      assert @licensed_repo.repository_license
      assert_equal "mit", @licensed_repo.license.key
    end

    test "when multiple licenses, sets all licenses" do
      assert_empty @three_licenses.repository_licenses
      RepositoryLicense.set_licenses(@three_licenses)
      @three_licenses.reload

      assert_equal "mit", @three_licenses.license.key
      assert_equal 3, @three_licenses.repository_licenses.count
    end

    test "does not create duplicates" do
      assert_empty @three_licenses.repository_licenses
      RepositoryLicense.set_licenses(@three_licenses)
      RepositoryLicense.set_licenses(@three_licenses)
      @three_licenses.reload

      assert_equal "mit", @three_licenses.license.key
      assert_equal 3, @three_licenses.repository_licenses.count
    end

    test "ignores matches if another file with duplicate name is detected" do
      assert_empty @duplicate_licenses.repository_licenses
      RepositoryLicense.set_licenses(@duplicate_licenses)

      @duplicate_licenses.reload

      assert_equal 1, @duplicate_licenses.repository_licenses.count
      assert_equal "mit", @duplicate_licenses.license.key
      assert_equal "./LICENSE", @duplicate_licenses.repository_license.filepath
    end

    test "ignores invalid license files" do
      assert_empty @invalid_licenses.repository_licenses
      RepositoryLicense.set_licenses(@invalid_licenses)

      @invalid_licenses.reload

      assert_equal 1, @invalid_licenses.repository_licenses.count
      assert_equal "mit", @invalid_licenses.license.key
      assert_equal "./LICENSE", @invalid_licenses.repository_license.filepath
    end
  end

  test "detects a repo's license" do
    assert_equal "mit", RepositoryLicense.detect_license(@licensed_repo)
    assert_equal "no-license", RepositoryLicense.detect_license(@unlicensed_repo)
    assert_equal "no-license", RepositoryLicense.detect_license(@copyrighted_repo)
  end

  test "knows when a license file exists but doesn't match a known license" do
    # Awaiting upstream fix. See https://github.com/github/gitrpc/pull/353
    # assert_equal "other", RepositoryLicense.detect_license(@other_license)
    assert_equal "other", RepositoryLicense.set_license(@other_license).key
    @other_license.reload
    assert_equal 0, @other_license.repository_license.license_id
    assert_equal "other", @other_license.license.key
  end

  test "sets the project's license" do
    assert_equal "mit", RepositoryLicense.set_license(@licensed_repo).key
    @licensed_repo.reload
    assert @licensed_repo.repository_license
    assert_equal "mit", @licensed_repo.license.key

    @unlicensed_repo.set_license
    refute @unlicensed_repo.repository_license
  end

  test "includes filepath" do
    assert_equal "mit", RepositoryLicense.set_license(@licensed_repo).key
    @licensed_repo.reload
    assert @licensed_repo.repository_license
    assert_equal "mit", @licensed_repo.license.key
    assert_equal "./LICENSE", @licensed_repo.repository_license.filepath
  end

  test "detects license when license is created via template" do
    repo = create :repository, name: "repo", owner: @user
    repo.license_template = "mit"
    repo.created_by_user_id = @user.id

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      assert_performed_with(job: RepositorySetLicenseJob, args: [repo]) do
        # This is necessary because initialize_git_repository_templates triggers a RockQueue job
        # that hits lifecycle callbacks that are what queue up RepositorySetLicenseJob
        repo.initialize_git_repository_templates
        assert_equal License["mit"], repo.reload.repository_license.license
      end
    end
  end

  test "detects the license when the default branch is changed" do
    repo = create :repository, name: "repo", owner: @user
    repo.license_template = "mit"
    repo.created_by_user_id = @user.id
    repo.initialize_git_repository_templates

    assert_enqueued_with(job: RepositorySetLicenseJob, args: [repo]) do
      # The branch needs to 'exist' for update_default_branch to work
      repo.heads.stub(:exist?, true) do
        repo.update_default_branch "something"
      end
    end
  end

  test "removes existing licenses when no valid licenses detected after change" do
    repo = create :repository, name: "previously-licensed-repo", owner: @user, created_by_user_id: @user.id, from_example: :license_markdown
    repo.license_template = "mit"
    repo.initialize_git_repository_templates

    RepositoryLicense.set_licenses(repo)
    repo.reload
    assert_equal 1, repo.repository_licenses.size

    ref = repo.heads[repo.owner_default_new_repo_branch]
    ref.append_commit({ message: "overwrite valid license", committer: repo.owner }, repo.owner) do |files|
      files.add "LICENSE", "Copyright (C) 2021-2022 by monalisa, all rights reserved."
    end
    ref.target_oid

    RepositoryLicense.set_licenses(repo)
    repo.reload

    assert_equal 0, repo.repository_licenses.size
  end
end
