# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersReviewRequestFilterTest < GitHub::TestCase
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
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    should_filter = { bool: { should: [
      { term: { requested_reviewer_ids: @mojombo.id } },
      { term: { requested_reviewer_team_ids: @team.id } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_equal should_filter, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "filters are nil when no user qualifier set" do
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    should_filter = { bool: { should: [
      { term: { requested_reviewer_ids: @mojombo.id } },
      { term: { requested_reviewer_team_ids: @team.id } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_nil filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "doesn't blow up if org login is provided" do
    @quals[:user].must "ian"
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { term: { requested_reviewer_ids: @org.id } }

    must_not_filter = [{ term: { author_id: @org.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "generates a term filter when a part of no teams" do
    @quals[:user].must "TwP"
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { term: { requested_reviewer_ids: @twp.id } }

    must_not_filter = [{ term: { author_id: @twp.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a should filter with multiple users" do
    @quals[:user].must %w[mojombo TwP]
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { bool: { should: [
      { terms: { requested_reviewer_ids: [@mojombo.id, @twp.id] } },
      { term: { requested_reviewer_team_ids: @team.id } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } },
      { term: { author_id: @twp.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a should filter with multiple teams" do
    team2 = create(:team, organization: @org, name: "team yay", privacy: :closed)
    team2.add_member(@mojombo)

    @quals[:user].must "mojombo"
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { bool: { should: [
      { term: { requested_reviewer_ids: @mojombo.id } },
      { terms: { requested_reviewer_team_ids: [@team.id, team2.id] } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a should filter with multiple teams does not include secret teams" do
    team2 = create(:team, organization: @org, name: "team yay")
    team2.add_member(@mojombo)

    @quals[:user].must "mojombo"
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { bool: { should: [
      { term: { requested_reviewer_ids: @mojombo.id } },
      { term: { requested_reviewer_team_ids: @team.id } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a should filter with nested teams" do
    parent_team = create(:team, organization: @org, name: "parent-team", privacy: :closed)
    child_team = create(:team, organization: @org, name: "child-team", privacy: :closed, parent_team_id: parent_team.id)
    child_child_team = create(:team, organization: @org, name: "child-child-team", privacy: :closed, parent_team_id: child_team.id)
    child_child_team.add_member(@mojombo)

    @quals[:user].must "mojombo"
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    expected = { bool: { should: [
      { term: { requested_reviewer_ids: @mojombo.id } },
      { terms: { requested_reviewer_team_ids: [@team.id, parent_team.id, child_team.id, child_child_team.id] } },
    ] } }

    must_not_filter = [{ term: { author_id: @mojombo.id } }]

    assert_equal expected, filter.must
    assert_equal must_not_filter, filter.must_not
    assert filter.valid?
  end

  test "creates a missing filter" do
    team2 = create(:team, organization: @org, name: "team yay", privacy: :closed)
    team2.add_member(@mojombo)

    @quals[:user].must :missing
    filter = Search::Filters::ReviewRequestFilter.new(keys: :user, qualifiers: @quals, exclude_private_profiles: false)

    assert_equal({ bool: { must_not: [{ exists: { field: :requested_reviewer_ids } },
      { exists: { field: :requested_reviewer_team_ids } }] } }, filter.must)
    assert filter.valid?, "filter should be valid"
  end
end
