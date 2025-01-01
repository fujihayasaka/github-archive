# typed: strict
# frozen_string_literal: true

require "test_helper"

class Search::Filters::RepoIdFilterTest < GitHub::TestCase
  test "builds a term filter" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [1, 2]

    assert_equal({ terms: { repo_id: [1, 2] } }, filter.must)
    refute filter.blank?
  end

  test "an empty filter should exclude every repo to avoid leaking non-accessible ones" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, []

    assert_equal({ terms: { repo_id: [] } }, filter.must)
  end

  test "builds a term filter with public and private repos" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [1, 2], also_public: true
    assert filter.valid?
    expected_hash = { bool: { should: [
      { terms: { repo_id: [1, 2] } },
      { term: { visibility: "public" } },
    ] } }
    assert_equal(expected_hash, filter.must)
  end

  test "builds a term filter with internal and private repos" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [1, 2], also_internal: true
    expected_hash = { bool: { should: [
      { terms: { repo_id: [1, 2] } },
      { term: { visibility: "internal" } },
    ] } }
    assert_equal(expected_hash, filter.must)
  end

  test "builds a term filter with public and internal and private repos" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [1, 2], also_public: true, also_internal: true
    expected_hash = { bool: { should: [
      { terms: { repo_id: [1, 2] } },
      { terms: { visibility: %w[public internal] } },
    ] } }
    assert_equal(expected_hash, filter.must)
  end

  test "builds a term filter with public and internal repos" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [], also_public: true, also_internal: true
    assert_equal({ terms: { visibility: %w[public internal] } }, filter.must)
  end

  test "builds a term filter with public repos" do
    filter = Search::Filters::RepoIdFilter.new :repo_id, [], also_public: true
    assert_equal({ term: { visibility: "public" } }, filter.must)
  end
end
