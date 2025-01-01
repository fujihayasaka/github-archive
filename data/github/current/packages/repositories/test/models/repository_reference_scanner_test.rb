# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryReferenceScannerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "returns a single repository references"  do
    repo = create(:repository, owner: @user)
    text = "this is a repository reference #{GitHub.url}/#{repo.nwo}"
    scanner = RepositoryReferenceScanner.new(text: text, viewer: @user)
    references = scanner.references

    assert_equal repo, references.first
  end

  test "returns multiple repository references" do
    repo = create(:repository, owner: @user)
    other_repo = create(:repository, owner: @user)
    text = "this is a repository reference #{GitHub.url}/#{repo.nwo} and also #{GitHub.url}/#{other_repo.nwo}"
    scanner = RepositoryReferenceScanner.new(text: text, viewer: @user)

    references = scanner.references

    assert_equal 2, references.length
    assert_includes [repo, other_repo], references.first
    assert_includes [repo, other_repo], references.last
  end

  test "returns nothing for a non-existant repository" do
    text = "this is a repository reference #{GitHub.url}/fakeyuser/fakeyrepo"
    scanner = RepositoryReferenceScanner.new(text: text, viewer: @user)

    assert_empty scanner.references
  end

  test "returns nothing if the repository is not readable by the viewer" do
    repo = create(:private_repository)
    text = "this is a repository reference #{GitHub.url}/#{repo.nwo}"
    scanner = RepositoryReferenceScanner.new(text: text, viewer: @user)

    assert_empty scanner.references
  end
end
