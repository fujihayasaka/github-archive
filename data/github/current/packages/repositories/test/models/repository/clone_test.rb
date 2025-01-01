# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCloneTest < GitHub::TestCase
  include HydroTestHelpers
  fixtures do
    @repo = create(:repository, from_example: :simple)

    @blank_repo = create(:repository)
    @blank_repo.rpc.remove

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context ".clone_from_repo" do
    test "does nothing if source repo is nil" do
      Repository::Clone.from_repo(source_repo: nil, destination_repo: @blank_repo)
      @blank_repo.reload

      refute_predicate @blank_repo, :exists_on_disk?
      assert_predicate @blank_repo, :empty?
    end
    test "copies the Git repository content from source repository" do
      refute_predicate @repo, :empty?

      Repository::Clone.from_repo(source_repo: @repo, destination_repo: @blank_repo)
      @blank_repo.reload

      assert_predicate @blank_repo, :exists_on_disk?
      refute_predicate @blank_repo, :empty?
      assert_equal @blank_repo.refs.find("master").target_oid, @repo.refs.find("master").target_oid
    end

    test "correctly sets up the nwo file" do
      Repository::Clone.from_repo(source_repo: @repo, destination_repo: @blank_repo)

      assert_equal @blank_repo.nwo, @blank_repo.rpc.fs_read("info/nwo")
    end

    test "correctly sets up the hooks symlink" do
      Repository::Clone.from_repo(source_repo: @repo, destination_repo: @blank_repo)

      if GitHub.enterprise?
        hooks_path = File.readlink("#{@blank_repo.shard_path}/hooks")
        assert_equal hooks_path, "#{GitHub.repository_template}/hooks"
      else
        assert_raises(Errno::ENOENT) { File.stat("#{@blank_repo.shard_path}/hooks") }
      end
    end
  end

  context "Hydro events" do
    test "emits message when internal clone complete", skip_enterprise: true do
      Repository::Clone.from_repo(source_repo: @repo, destination_repo: @blank_repo)

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.InternalCloneComplete")
    end
  end
end
