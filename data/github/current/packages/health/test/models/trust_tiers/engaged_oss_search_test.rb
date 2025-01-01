# typed: true
# frozen_string_literal: true

require "test_helper"

class TrustTiers::EngagedOssSearchTest < GitHub::TestCase
  fixtures do
    @public_repo = create(:repository, name: "public-repo-1")
    @private_repo = create(:private_repository, name: "private-repo-1")

    make_searchable @public_repo
    make_searchable @private_repo
  end

  test "returns results filtered by query_phrase" do
    query_phrase = "is:public"
    search_top = 2
    results = TrustTiers::EngagedOssSearch.search(query_phrase, search_top)

    assert_equal 1, results.count
    assert_equal @public_repo.nwo, results[0][:nwo]
  end
end
