# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPathCheckingTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test "indicates whether file exists" do
    example_repo :defunkt_ambition, @repo

    assert  @repo.includes_file?("Rakefile")
    assert !@repo.includes_file?("yermom")

    assert  @repo.includes_file?("lib/ambition/query.rb")
    assert !@repo.includes_file?("lib/ambition/yermom")
  end

  test "can check file on other branches" do
    example_repo :pull_request_fork, @repo

    assert !@repo.includes_file?("file11")
    assert !@repo.includes_file?("file11", "master")
    assert  @repo.includes_file?("file11", "behind")

    assert  @repo.includes_file?("big-one")
    assert  @repo.includes_file?("big-one", "master")
    assert !@repo.includes_file?("big-one", "behind")
  end

  test "checks for files on repo-defined default branch by default" do
    example_repo :pull_request_fork, @repo

    assert !@repo.includes_file?("file11")
    assert  @repo.includes_file?("big-one")

    @repo.default_branch = "behind"

    assert  @repo.includes_file?("file11")
    assert !@repo.includes_file?("big-one")
  end

  test "returns false for files if the branch does not exist" do
    example_repo :pull_request_fork, @repo

    assert !@repo.includes_file?("big-one", "thisbranchisnothere")
  end

  test "returns false for files if the directory path does not exist" do
    example_repo :pull_request_fork, @repo

    assert !@repo.includes_file?("how/about/this/path")
  end

  test "indicates whether a path is a directory" do
    example_repo :defunkt_ambition, @repo

    assert  @repo.includes_directory?("lib")
    assert !@repo.includes_directory?("yermom")
    assert !@repo.includes_directory?("Rakefile")  # n.b. this is an existing *file*

    assert  @repo.includes_directory?("lib/ambition")
    assert !@repo.includes_directory?("lib/yermom")
    assert !@repo.includes_directory?("lib/ambition.rb")  # n.b. this is an existing *file*
  end

  test "can check directory on other branches" do
    skip "looking for a repo that has branches and directories, or have to make one"
    example_repo :defunkt_facebox, @repo

    assert !@repo.includes_file?("file11")
    assert !@repo.includes_file?("file11", "master")
    assert  @repo.includes_file?("file11", "behind")

    assert  @repo.includes_file?("big-one")
    assert  @repo.includes_file?("big-one", "master")
    assert !@repo.includes_file?("big-one", "behind")
  end

  test "checks for directories on repo-defined default branch by default" do
    skip "looking for a repo that has branches and directories, or have to make one"
    example_repo :defunkt_facebox, @repo

    assert !@repo.includes_file?("file11")
    assert  @repo.includes_file?("big-one")

    @repo.default_branch = "behind"

    assert  @repo.includes_file?("file11")
    assert !@repo.includes_file?("big-one")
  end

  test "returns false for directories if the branch does not exist" do
    example_repo :defunkt_ambition, @repo

    assert !@repo.includes_directory?("lib", "thisbranchisnothere")
  end

  test "returns false for directories if the directory path does not exist" do
    example_repo :defunkt_ambition, @repo

    assert !@repo.includes_directory?("how/about/this/path")
  end

  test "indicates whether a path is valid for file creation or editing" do
    example_repo :defunkt_ambition, @repo

    assert  @repo.valid_file_path?("Rakefile")
    assert  @repo.valid_file_path?("yermom")

    assert !@repo.valid_file_path?("Rakefile/thing")

    assert !@repo.valid_file_path?("lib")
    assert  @repo.valid_file_path?("lib/ambition/stuffgoeshere")
    assert !@repo.valid_file_path?("lib/ambition.rb/stuffgoeshere")
    assert  @repo.valid_file_path?("lib/ambition/stuff/goes/here")

    assert  @repo.valid_file_path?("how/about/this/path")
  end
end
