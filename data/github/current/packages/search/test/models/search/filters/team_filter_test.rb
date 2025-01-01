# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersTeamFilterTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @org = create(:organization, login: "ian", plan: "bronze", admin: @defunkt)
    @team = create :team, organization: @org, name: "Joy Division"
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:team].must "ian/Joy-Division"
  end

  test "non-authenticated users do not get to use the team filter" do
    filter = Search::Filters::TeamFilter.new \
      field: :team, qualifiers: @quals

    assert filter.valid?
    assert_nil filter.must
  end

  context "with a current user" do
    test "non-organization users do not get to see an organization teams" do
      filter = Search::Filters::TeamFilter.new \
        field: :team, qualifiers: @quals, current_user: @mojombo

      assert_equal false, filter.valid?
    end

    test "organization members can see the organization teams" do
      filter = Search::Filters::TeamFilter.new \
        field: :team, qualifiers: @quals, current_user: @defunkt

      assert filter.valid?
      assert_equal({ term: { team: @team.id } }, filter.must)
      assert_nil filter.must_not
    end

    test "illegal team slugs mark the filter as invalid" do
      @quals[:team].must "ian/illegal/team-slug"

      filter = Search::Filters::TeamFilter.new \
        field: :team, qualifiers: @quals, current_user: @defunkt

      assert_equal false, filter.valid?
      assert_equal '"ian/illegal/team-slug" is not a valid team name.', filter.invalid_reason
    end
  end

  context "when negated" do
    test "negates the team mention filter" do
      @quals[:team].clear
      @quals[:team].must_not "ian/Joy-Division"

      filter = Search::Filters::TeamFilter.new \
        field: :team, qualifiers: @quals, current_user: @defunkt

      assert filter.valid?
      assert_equal({ term: { team: @team.id } }, filter.must_not)
      assert_nil filter.must
    end
  end

  context "degenerate queries" do
    test "negative filter wins" do
      @quals[:team].must_not "ian/Joy-Division"

      filter = Search::Filters::TeamFilter.new \
        field: :team, qualifiers: @quals, current_user: @defunkt

      assert filter.valid?
      assert_equal({ term: { team: @team.id } }, filter.must_not)
      assert_nil filter.must
    end
  end

end
