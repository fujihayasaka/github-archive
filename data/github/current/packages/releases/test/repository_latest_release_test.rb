# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryLatestReleaseTest < GitHub::TestCase
  fixtures do
    @repo = create :repository, from_example: :repository_test_simple
    @release = create :release, repository: @repo
  end

  test "associations" do
    RepositoryLatestRelease.create(repository_id: @repo.id, release_id: @release.id)

    assert_equal @repo.repository_latest_release.release, @release
    assert_equal @release.repository_latest_release.repository, @repo
  end

  test "uniqueness" do
    release2 = create :release, repository: @repo
    RepositoryLatestRelease.create(repository_id: @repo.id, release_id: @release.id)

    # must be unique by repo_id
    assert_raises ActiveRecord::RecordNotUnique do
      RepositoryLatestRelease.create(repository_id: @repo.id, release_id: release2.id)
    end

    # must be unique by release_id
    repo2 = create :repository
    assert_raises ActiveRecord::RecordNotUnique do
      # validate: false here since otherwise this would be prevented by model validations since release doesn't belong to this repo
      # we want to check the uniqueness constraint here, not the model validation
      RepositoryLatestRelease.new(repository_id: repo2.id, release_id: @release.id).save(validate: false)
    end
  end

  test "validates release is not draft or prerelease" do
    draft = create :release, repository: @repo, draft: true
    prerelease = create :release, repository: @repo, prerelease: true

    model_for_draft = RepositoryLatestRelease.new(repository_id: @repo.id, release_id: draft.id)
    model_for_prerelease = RepositoryLatestRelease.new(repository_id: @repo.id, release_id: prerelease.id)

    assert_equal false, model_for_draft.valid?
    assert_equal false, model_for_prerelease.valid?
    assert_equal false, model_for_draft.save
    assert_equal false, model_for_prerelease.save
  end

  test "validates release belongs to repository" do
    different_repo = create :repository, from_example: :repository_test_simple
    different_repo_release = create :release, repository: different_repo

    model = RepositoryLatestRelease.new(repository_id: @repo.id, release_id: different_repo_release.id)
    assert_equal false, model.valid?
    assert_equal false, model.save
  end
end
