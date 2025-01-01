# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSuggestionsQueryTest < GitHub::TestCase
  def index
    @index ||= Elastomer::Indexes::Users.new
  end

  fixtures do
    @owner = create(:user, plan: "micro")
    @org_1 = create(:organization, login: "org-1", admin: @owner)
    @org_2 = create(:organization, login: "org-2", admin: @owner)
    @org_3 = create(:organization, login: "org-3", admin: @owner)
    @org_4 = create(:organization, login: "org-4", admin: @owner)
    @hello_world_org = create(:organization, login: "hello-world", admin: @owner)
    @business = create :business, organizations: [@org_1, @org_2, @org_3, @org_4, @hello_world_org], owners: [@owner]
  end

  setup do
    reset_search(index.name)
    make_searchable(@org_1, @org_2, @org_3, @org_4, @hello_world_org)
    @default_orgs = [@org_1, @org_2, @org_3, @org_4, @hello_world_org]
  end

  test "provides default suggestions when query is not provided" do
    query_results = Settings::OrganizationSuggestionsQuery.call(query: nil).to_a

    assert_same_elements @default_orgs, query_results
  end

  test "uses Organization scope when query is not provided" do
    other_org = create(:organization)
    scope = @owner.organizations
    query_results = Settings::OrganizationSuggestionsQuery.call(query: nil, scope: scope).to_a

    refute_includes query_results, other_org, "should exclude org that does not match the given scope"
    assert_same_elements @default_orgs, query_results
  end

  test "gives accurate suggestions based on query" do
    assert_equal [@hello_world_org], Settings::OrganizationSuggestionsQuery.call(query: "hello").to_a
  end

  test "an exact match gets prepended to results" do
    t_org = create(:organization, login: "tom", admin: @owner)
    tomato_org = create(:organization, login: "tomato", admin: @owner)
    make_searchable(t_org, tomato_org, refresh: true)

    results = Settings::OrganizationSuggestionsQuery.call(query: t_org.login).to_a

    assert_equal t_org, results.first
    assert_includes results, tomato_org
  end

  test "uses Organization scope when query is provided" do
    other_org = create(:organization, login: "hello-people") # matches query but will not match scope
    make_searchable(other_org)
    scope = @owner.organizations
    query_results = Settings::OrganizationSuggestionsQuery.call(query: "hello", scope: scope).to_a

    refute_includes query_results, other_org, "should exclude org that does not match the given scope"
    assert_equal [@hello_world_org], query_results
  end
end
