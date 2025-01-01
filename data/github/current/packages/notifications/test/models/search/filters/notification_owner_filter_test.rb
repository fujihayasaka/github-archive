# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersNotificationOwnerFilterTest < GitHub::TestCase
  fixtures do
    @org1 = create(:organization, login: "github")
    @org2 = create(:organization, login: "buhtig")
  end

  setup do
    @qualifiers = Search::ParsedQuery.qualifiers
  end

  test "generates an include filter for owner qualifier" do
    @qualifiers[:owner].must "github"
    filter = Search::Filters::NotificationOwnerFilter.new(qualifiers: @qualifiers)

    assert_equal({ term: { owner_id: @org1.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "generates an exclude filter for -owner qualifier" do
    @qualifiers[:owner].must_not "github"
    filter = Search::Filters::NotificationOwnerFilter.new(qualifiers: @qualifiers)

    assert_equal({ term: { owner_id: @org1.id } }, filter.must_not)
    assert_nil filter.must
    assert filter.valid?
  end

  test "generates an exclude filter for multiple owner qualifier" do
    @qualifiers[:owner].must_not %w[github buhtig]
    filter = Search::Filters::NotificationOwnerFilter.new(qualifiers: @qualifiers)

    assert_same_elements([@org1.id, @org2.id], filter.must_not[:terms][:owner_id])
    assert_nil filter.must
    assert filter.valid?
  end

  test "combines include and exclude filters" do
    @qualifiers[:owner].must "github"
    @qualifiers[:owner].must_not "buhtig"
    filter = Search::Filters::NotificationOwnerFilter.new(qualifiers: @qualifiers)

    assert_equal({ term: { owner_id: @org1.id } }, filter.must)
    assert_equal({ term: { owner_id: @org2.id } }, filter.must_not)
    assert filter.valid?
  end

  test "generates an include filter for multiple owner qualifier" do
    @qualifiers[:owner].must %w[github buhtig]
    filter = Search::Filters::NotificationOwnerFilter.new(qualifiers: @qualifiers)

    assert_same_elements([@org1.id, @org2.id], filter.must[:terms][:owner_id])
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "generates an exclude filter for unauthorized organizations" do
    filter = Search::Filters::NotificationOwnerFilter.new(
      qualifiers: @qualifiers,
      unauthorized_account_ids: [@org1.id],
    )

    assert_equal({ term: { owner_id: @org1.id } }, filter.must_not)
    assert_nil filter.must
    assert filter.valid?
  end

  test "combines exclude filter with unauthorized saml orgs" do
    @qualifiers[:owner].must_not "buhtig"
    filter = Search::Filters::NotificationOwnerFilter.new(
      qualifiers: @qualifiers,
      unauthorized_account_ids: [@org1.id],
    )

    assert_same_elements([@org1.id, @org2.id], filter.must_not[:terms][:owner_id])
    assert filter.valid?
  end

  test "does not set include filter if organization id is in unauthorized_account_ids array" do
    @qualifiers[:owner].must "github"

    filter = Search::Filters::NotificationOwnerFilter.new(
      qualifiers: @qualifiers,
      unauthorized_account_ids: [@org1.id],
    )

    assert_equal({ term: { owner_id: @org1.id } }, filter.must_not)
    assert_nil filter.must
    assert filter.valid?
  end
end
