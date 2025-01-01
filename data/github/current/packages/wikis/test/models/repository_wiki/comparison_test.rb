# typed: true
# frozen_string_literal: true

require "test_helper"

class WikiComparisonTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @member = create :user, created_at: 8.months.ago

    @pub_repo = create(:public_repository, owner: @member, has_wiki: true)
    @wiki = @pub_repo.unsullied_wiki
    @page = @wiki.pages.default
    @sha1 = "7bc7330f5dbcfa441fa5022db3a9bd526880ceb2"
    @sha2 = "f037b9521f6378af6cae13813f974c201e0bff97"
    @bad_sha = "9dce38e932ccd44eee383b520752d8faf5d190ad"

    example_repo :wiki, @wiki
  end

  test "can compare single revision" do
    versions = [@sha1, nil]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    assert comparison.comparable?
  end

  test "can compare two revisions" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    assert comparison.comparable?
  end

  test "can compare two revisions without page" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, nil, versions)
    assert comparison.comparable?
  end

  test "cannot compare same revisions" do
    versions = [@sha1, @sha1]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.comparable?
  end

  test "cannot compare invalid sha" do
    versions = [@sha1, @bad_sha]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.valid?
  end

  test "cannot compare without revisions" do
    versions = [nil, nil]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.valid?
  end

  test "can diff a valid comparsion" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    assert comparison.diff_available?
  end

  test "can diff a valid comparsion without a page" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, nil, versions)
    assert comparison.diff_available?
  end

  test "cannot diff an invalid comparsion" do
    versions = [@sha1, @bad_sha]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.valid?
  end

  test "cannot diff revision with nothing to compare" do
    versions = [@inital_commit, nil]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.valid?
  end

  test "can revert revisions if user has write access" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    assert comparison.revertable_by?(@member)
  end

  test "cannot revert revisions if user is not logged in" do
    versions = [@sha1, @sha2]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.revertable_by?(nil)
  end

  test "cannot revert single revision" do
    versions = [@sha1, nil]

    comparison = RepositoryWiki::Comparison.new(@wiki, @page, versions)
    refute comparison.revertable_by?(@member)
  end
end
