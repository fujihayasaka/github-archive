# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryDefaultBranchTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @repo = create(:repository)

    metadata = { message: "blah", committer: @repo.owner }
    commit = @repo.commits.create(metadata) {}

    @repo.heads.create("master", commit, @repo.owner)
    @repo.heads.create("other", commit, @repo.owner)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @repo.update_default_branch("master")
    reset_hydro # Flush any messages from the line above
  end

  test "is 'master' by default" do
    assert_equal "master", @repo.default_branch
  end

  test "can be set to a different branch" do
    branch = "something"

    @repo.heads.create(branch, @repo.default_oid, @repo.owner) unless @repo.heads.find(branch)
    @repo.update_default_branch(branch)
    assert_equal branch, @repo.default_branch
  end

  if !TestEnv.test_all_features?
    test "can instrument default branch change for search indexing", skip_enterprise: true do
      multibranch_user = create(:user)
      multibranch_repo = create(:repository, owner: multibranch_user, from_example: :simple)

      branch = "v2_develop"
      expected_ref = "refs/heads/#{branch}"

      multibranch_repo.heads.create(branch, multibranch_repo.default_oid, multibranch_repo.owner) unless multibranch_repo.heads.find(branch)
      multibranch_repo.update_default_branch(branch)

      assert_hydro_published({
        change: :DEFAULT_BRANCH_CHANGED,
        repository: Hydro::EntitySerializer.repository(multibranch_repo),
        ref: expected_ref,
        owner_name: multibranch_repo.owner.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")

      message = GitHub.hydro_publisher.sink.messages.detect do |m|
        m.schema == "github.search.v0.RepositoryChanged" &&
          m.partition_key == multibranch_repo.id
      end

      refute_nil message

      repository_changed = decode_hydro_message(message.data).message
      assert_equal :DEFAULT_BRANCH_CHANGED, repository_changed.fetch(:change)
      assert_equal multibranch_repo.id, repository_changed.fetch(:repository).fetch(:id)
      assert_equal multibranch_repo.owner.name, repository_changed.fetch(:owner_name)
      assert_equal branch, repository_changed.fetch(:repository).fetch(:default_branch)
      assert_equal expected_ref, repository_changed.fetch(:ref)
    end
  end

  test "can contain 4-byte unicode" do
    branch = "\xF0\x9F\x8D\xB7wine"
    @repo.heads.create(branch, @repo.default_oid, @repo.owner)
    @repo.default_branch = branch
    @repo.save
    assert_equal branch, @repo.default_branch
  end

  test "deleting the default branch" do
    example_repo_snapshot

    assert_equal "master", @repo.default_branch

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      @repo.heads.find("master").delete(@repo.owner)
    end

    @repo.reload

    assert_nil @repo.heads.find("master")
    assert_equal "other", @repo.default_branch

    example_repo_restore
  end
end
