# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersUserReviewRequestFilterTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP")
    @org = create(:organization, login: "ian", plan: "bronze", admin: @defunkt)
    @team = create(:team, organization: @org, name: "Joy Division", privacy: :closed)
    @team.add_member(@mojombo)
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "generates a should and must not filter" do
    @quals[:user].must "mojombo"
    filter = Search::Filters::UserReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    should_filter = { term: { requested_reviewer_ids: @mojombo.id } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_equal should_filter, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "filters are nil when no user qualifier set" do
    filter = Search::Filters::UserReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_nil filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "doesn't blow up if org login is provided" do
    @quals[:user].must "ian"
    filter = Search::Filters::UserReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { term: { requested_reviewer_ids: @org.id } }

    must_not_filter = [{ term: { author_id: @org.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a should filter with multiple users" do
    @quals[:user].must %w[mojombo TwP]
    filter = Search::Filters::UserReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { terms: { requested_reviewer_ids: [@mojombo.id, @twp.id] } }

    must_not_filter = [
      { term: { author_id: @mojombo.id } },
      { term: { author_id: @twp.id } }
    ]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end
end
