# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class DirectoryTestBase < GitHub::TestCase

  fixtures do
    Spokesd.enable_spokesd
    @repo = create(:repository)
    @empty_repo = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd
    example_repo :readmes, @repo
    example_repo :readme_none, @empty_repo
    @directory = @repo.directory("master")
  end
end

class DirectoryTest < DirectoryTestBase
  test "calculates actual commit OID for given committish" do
    assert_equal @repo.ref_to_sha("master"), @directory.send(:commit_sha)
  end

  test "returns an empty tree content list for a bad path" do
    assert_raises GitRPC::NoSuchPath do
      @repo.directory("master", "some/crap").tree_entries
    end
  end

  test "equality" do
    assert_equal @directory, @directory.dup
    assert_equal @directory, Directory.new(@repo, "master", "")
  end

  test "preferred_readme" do
    refute_nil @directory.preferred_readme
    assert_equal "README.md", @directory.preferred_readme.name
  end

  test "preferred_readme rescues GitRpc::ObjectMissing" do
    PreferredFile.expects(:find).raises(GitRPC::ObjectMissing)
    assert_nil @directory.preferred_readme
  end

  test "can_compute_history? returns false if tree history over max tree size" do
    @directory.tree_history.expects(:over_max_tree_size?).returns(true)
    refute_predicate @directory, :can_compute_history?
  end

  test "can_compute_history? returns true if tree history not over max tree size" do
    @directory.tree_history.expects(:over_max_tree_size?).returns(false)
    assert_predicate @directory, :can_compute_history?
  end
end

class DirectoryTransactionalTest < DirectoryTestBase
  Spokesd.share_spokesdb(self)

  test "prefer first readme" do
    ref  = @repo.heads.find("master")
    user = @repo.owner
    metadata = { committer: user }

    metadata[:message] = "add .rmd readme"
    ref.append_commit(metadata, user) do |files|
      files.add("README.rmd", "some content")
    end
    @directory = @repo.directory("master")
    assert_equal "README.md", @directory.preferred_readme.name

    metadata[:message] = "add .Rmd readme"
    ref.append_commit(metadata, user) do |files|
      files.add("README.Rmd", "some content")
    end
    @directory = @repo.directory("master")
    assert_equal "README.md", @directory.preferred_readme.name
  end

  test "will prefer a non binary readme with an unrecognized extension" do
    ref  = @repo.heads.find("master")
    user = @repo.owner
    metadata = { committer: user }

    metadata[:message] = "Rename using Chemical-X"
    ref.append_commit(metadata, user) do |files|
      files.move "README.md", "README.powerpuffgirl", "Sugar, spice, and everything nice"
    end
    @directory = @repo.directory("master")
    assert_equal "README.powerpuffgirl", @directory.preferred_readme.name
  end

  test "never prefers a binary readme regardless of extension" do
    ref  = @repo.heads.find("master")
    user = @repo.owner
    metadata = { committer: user }

    metadata[:message] = "Rename using Chemical-X"
    ref.append_commit(metadata, user) do |files|
      files.remove "README.md"
      files.add  "README.gif", File.read("#{Rails.root}/test/fixtures/icons-000000.png")
    end
    @directory = @repo.directory("master")
    assert_nil @directory.preferred_readme
  end

  test "prefers formatted readme over readme with unrecognized extension" do
    ref  = @repo.heads.find("master")
    user = @repo.owner
    metadata = { committer: user }

    metadata[:message] = "Rename using Chemical-X"
    ref.append_commit(metadata, user) do |files|
      files.move "README.md", "README.powerpuffgirl", "Sugar, spice, and everything nice"
    end
    @directory = @repo.directory("master")
    assert_equal "README.powerpuffgirl", @directory.preferred_readme.name

    metadata[:message] = "add markdown readme"
    ref.append_commit(metadata, user) do |files|
      files.add("README.md", "### some markdown content")
    end
    @directory = @repo.directory("master")
    assert_equal "README.md", @directory.preferred_readme.name
  end

  test "prefers formatted readme over readme with unrecognized extension even if the formatted version alpha-sorts later" do
    ref  = @repo.heads.find("master")
    user = @repo.owner
    metadata = { committer: user }

    metadata[:message] = "Rename for reasons"
    ref.append_commit(metadata, user) do |files|
      files.move "README.md", "README.ext", "Ruby is awesome :heart:"
    end
    @directory = @repo.directory("master")
    assert_equal "README.ext", @directory.preferred_readme.name

    metadata[:message] = "add markdown readme"
    ref.append_commit(metadata, user) do |files|
      files.add("README.md", "### m comes after e")
    end
    @directory = @repo.directory("master")
    assert_equal "README.md", @directory.preferred_readme.name
  end

  test "differentiates commits that last touched blobs with the same content" do
    ref = @repo.heads.find("master")
    metadata = { message: "blah", committer: @repo.owner }

    commit_1 = ref.append_commit(metadata, @repo.owner) do |files|
      files.add("blob_1", "content")
    end

    commit_2 = ref.append_commit(metadata, @repo.owner) do |files|
      files.add("blob_2", "content")
    end

    directory = @repo.directory("master")
    directory.tree_history.calculate_all_entries

    items = directory.items.index_by { |i| i[:name] }

    assert_equal commit_1, items["blob_1"][:commit]
    assert_equal commit_2, items["blob_2"][:commit]
  end

  test "works correctly with whitespace in tree entries" do
    ref = @repo.heads.find("master")
    metadata = { message: "blah", committer: @repo.owner }

    commit_1 = ref.append_commit(metadata, @repo.owner) do |files|
      files.add(" blob_space1 ", "content")
    end

    commit_2 = ref.append_commit(metadata, @repo.owner) do |files|
      files.add(" blob_space2 ", "content")
    end

    directory = @repo.directory("master")
    directory.tree_history.calculate_all_entries

    items = directory.items.index_by { |i| i[:name] }

    assert_equal commit_1, items[" blob_space1 "][:commit]
    assert_equal commit_2, items[" blob_space2 "][:commit]
  end
end
