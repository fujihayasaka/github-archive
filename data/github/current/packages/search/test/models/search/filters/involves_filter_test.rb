# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersInvolvesFilterTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP")
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
    @options = {
      field: [:author_id, :assignee_id, :mention_ids],
      keys: :involves,
      qualifiers: @quals,
      exclude_private_profiles: false
    }
  end

  test "generates a must filter" do
    @quals[:involves].must "defunkt"
    filter = Search::Filters::InvolvesFilter.new @options

    expected = { bool: { should: [
      { term: { author_id: @defunkt.id } },
      { term: { assignee_id: @defunkt.id } },
      { term: { mention_ids: @defunkt.id } },
    ] } }

    assert_equal expected, filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "removes excluded users from the must filter" do
    @quals[:involves].must %w[defunkt mojombo TwP]
    @quals[:involves].must_not "mojombo"
    filter = Search::Filters::InvolvesFilter.new @options

    expected = { bool: { should: [
      { terms: { author_id: [@defunkt.id, @twp.id] } },
      { terms: { assignee_id: [@defunkt.id, @twp.id] } },
      { terms: { mention_ids: [@defunkt.id, @twp.id] } },
    ] } }

    assert_equal expected, filter.must
    assert filter.valid?
  end

  test "generates an must not filter" do
    @quals[:involves].must_not "mojombo"
    filter = Search::Filters::InvolvesFilter.new @options

    expected = [
      { term: { author_id: @mojombo.id } },
      { term: { assignee_id: @mojombo.id } },
      { term: { mention_ids: @mojombo.id } },
    ]

    assert_equal expected, filter.must_not
    assert_nil filter.must
    assert filter.valid?
  end

  test "ignores spammy users" do
    @quals[:involves].must %w[TwP hushpuppy1234]
    filter = Search::Filters::InvolvesFilter.new @options

    expected = { bool: { should: [
      { term: { author_id: @twp.id } },
      { term: { assignee_id: @twp.id } },
      { term: { mention_ids: @twp.id } },
    ] } }

    assert_equal expected, filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  context "with non-existent users" do
    test "the filter will be invalid" do
      @quals[:involves].must "non-existent-user"
      filter = Search::Filters::InvolvesFilter.new @options

      assert_nil filter.must
      assert !filter.valid?
    end

    test "the filter will not be valid" do
      @quals[:involves].must "twp"
      @quals[:involves].must_not "non-existent-user"
      filter = Search::Filters::InvolvesFilter.new @options

      expected = { bool: { should: [
        { term: { author_id: @twp.id } },
        { term: { assignee_id: @twp.id } },
        { term: { mention_ids: @twp.id } },
      ] } }

      assert_equal expected, filter.must
      assert_nil filter.must_not
      assert !filter.valid?
    end
  end

  context "degenerate inputs" do
    test "creates a valid filter" do
      @quals[:involves].must "mojombo"
      @quals[:involves].must_not "mojombo"
      filter = Search::Filters::InvolvesFilter.new @options

      expected = [
        { term: { author_id: @mojombo.id } },
        { term: { assignee_id: @mojombo.id } },
        { term: { mention_ids: @mojombo.id } },
      ]

      assert_nil filter.must
      assert_equal expected, filter.must_not
      assert filter.valid?, "filter should be valid"
    end

    test "still creates a valid filter" do
      @quals[:involves].must %w[defunkt mojombo]
      @quals[:involves].must_not "mojombo"
      filter = Search::Filters::InvolvesFilter.new @options

      expected = { bool: { should: [
        { term: { author_id: @defunkt.id } },
        { term: { assignee_id: @defunkt.id } },
        { term: { mention_ids: @defunkt.id } },
      ] } }
      assert_equal expected, filter.must

      expected = [
        { term: { author_id: @mojombo.id } },
        { term: { assignee_id: @mojombo.id } },
        { term: { mention_ids: @mojombo.id } },
      ]
      assert_equal expected, filter.must_not

      assert filter.valid?, "filter should be valid"
    end
  end
end
