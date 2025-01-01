# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersDateRangeFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "builds a term filter" do
    @quals[:created].must "2013-12-25T08:00"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert_equal({ term: { created: "2013-12-25T08:00" } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "single day filter" do
    @quals[:created].must "2011-12-27"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gte: "2011-12-27||/d", lte: "2011-12-27||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "doesn't explode with booleans" do
    @quals[:merged].must "false"
    assert_nothing_raised do
      Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    end
    @quals[:merged].clear

    @quals[:merged].must "true"
    assert_nothing_raised do
      Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    end
  end

  test "greater-than filter" do
    @quals[:created].must ">2011-12-27"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gt: "2011-12-27||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?

    @quals[:created].clear
    @quals[:created].must "2011-12-27..*"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gte: "2011-12-27||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "less-than filter" do
    @quals[:created].must "<2011-01-01"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { lt: "2011-01-01||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?

    @quals[:created].clear
    @quals[:created].must "*..2011-12-27"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { lte: "2011-12-27||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?

    @quals[:created].clear
    @quals[:created].must "<=2011-12-27"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { lte: "2011-12-27||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "bounded range filter" do
    @quals[:created].must "2011-12-27..2011-12-30"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gte: "2011-12-27||/d", lte: "2011-12-30||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "range filter bounded by year and specific day" do
    @quals[:created].must "2014 .. 2014-05-01"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gte: "2014||/y", lte: "2014-05-01||/d" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "range filter bounded by year and specific day with zone" do
    @quals[:created].must "2014 .. 2016-09-24T15:04:30-07:00"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ range: { created: { gte: "2014||/y", lte: "2016-09-24T15:04:30-07:00" } } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "unbounded range filter" do
    @quals[:created].must "* .. *"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_nil filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "array of range filters" do
    @quals[:created].must ["* .. 2011-12-27", ">= 2011-12-01", "2011-12-28"]
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

    assert_equal({ bool: { should: [
        { range: { created: { lte: "2011-12-27||/d" } } },
        { range: { created: { gte: "2011-12-01||/d" } } },
        { range: { created: { gte: "2011-12-28||/d", lte: "2011-12-28||/d" } } },
    ] } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "empty array" do
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert_nil filter.must
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "validates ISO8601 dates" do
    @quals[:created].must "2013-13"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert !filter.valid?
    assert_equal '"2013-13" is not a recognized date/time format. Please provide an ISO 8601 date/time value, such as YYYY-MM-DD.', filter.invalid_reason

    @quals.clear
    @quals[:created].must "2013-01 .. 2013-13"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert !filter.valid?
    assert_equal '"2013-13" is not a recognized date/time format. Please provide an ISO 8601 date/time value, such as YYYY-MM-DD.', filter.invalid_reason

    @quals.clear
    @quals[:created].must "<= foo"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert !filter.valid?
    assert_equal '"foo" is not a recognized date/time format. Please provide an ISO 8601 date/time value, such as YYYY-MM-DD.', filter.invalid_reason

    @quals.clear
    @quals[:created].must "2013-12-31 .. 2013-12-01"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert !filter.valid?
    assert_equal "the lower bound of the range (2013-12-31 .. 2013-12-01) is greater than the upper bound", filter.invalid_reason

    @quals.clear
    @quals[:created].must "2013 .. 2014-12-01"
    filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
    assert filter.valid?
  end

  context "when negated" do
    test "builds a not filter" do
      @quals[:created].must_not "2013-12-25T08:00"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ term: { created: "2013-12-25T08:00" } }, filter.must_not)
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must_not "2011-12-27"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ range: { created: { gte: "2011-12-27||/d", lte: "2011-12-27||/d" } } }, filter.must_not)
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must_not "> 2011-12-27"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ range: { created: { gt: "2011-12-27||/d" } } }, filter.must_not)
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must_not "< 2011-12-27"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ range: { created: { lt: "2011-12-27||/d" } } }, filter.must_not)
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must_not "2011-11-27 .. 2011-12-27"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ range: { created: { gte: "2011-11-27||/d", lte: "2011-12-27||/d" } } }, filter.must_not)
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must_not ["* .. 2011-12-27", ">= 2011-12-01", "2011-12-28"]
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      assert_nil filter.must
      assert_equal({ bool: { should: [
          { range: { created: { lte: "2011-12-27||/d" } } },
          { range: { created: { gte: "2011-12-01||/d" } } },
          { range: { created: { gte: "2011-12-28||/d", lte: "2011-12-28||/d" } } },
      ] } }, filter.must_not)
      assert filter.valid?
    end
  end

  context "when searching single values" do
    test "searches over an entire year" do
      @quals[:created].must "2016"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ range: { created: { gte: "2016||/y", lte: "2016||/y" } } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "searches over an entire month" do
      @quals[:created].must "2016-09"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ range: { created: { gte: "2016-09||/M", lte: "2016-09||/M" } } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "searches over a whole day" do
      @quals[:created].must "2016-09-24"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ range: { created: { gte: "2016-09-24||/d", lte: "2016-09-24||/d" } } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "searches over a single hour" do
      @quals[:created].must "2016-09-24T15"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ range: { created: { gte: "2016-09-24T15||/h", lte: "2016-09-24T15||/h" } } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "does not expand minutes or seconds" do
      @quals[:created].must "2016-09-24T15:04"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ term: { created: "2016-09-24T15:04" } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?

      @quals[:created].clear
      @quals[:created].must "2016-09-24T15:04:30"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ term: { created: "2016-09-24T15:04:30" } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end
  end

  context "time zones" do
    test "it handles them" do
      @quals[:created].must "2016-09-24T15:04:30Z"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ term: { created: "2016-09-24T15:04:30Z" } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end

    test "it handles numeric time zones, too" do
      @quals[:created].must "2016-09-24T15:04:30-07:00"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert_equal({ term: { created: "2016-09-24T15:04:30-07:00" } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
    end
  end

  context "invalid date range" do
    test "with numeric years" do
      @quals[:created].must "2016 .. 2015"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      refute filter.valid?
    end

    test "with time with zone and year" do
      @quals[:created].must "2016-09-24T15:04:30-07:00 .. 2015"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      refute filter.valid?
    end
  end

  context "malformed date-time strings" do
    test "with invalid numeric numbers" do
      @quals[:created].must "2022-01-240"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      refute filter.valid?

      @quals[:created].must "2022-00-24"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      refute filter.valid?

      @quals[:created].must "2022-012-24"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)
      refute filter.valid?
    end

    test "it handles US date formats with a validation error" do
      @quals[:created].must "14-07-2016"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      refute filter.valid?, "we do not support US format dates"
    end

    test "it limits years to the range 1970 to 2970" do
      @quals[:created].must "1962-02-23"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      refute filter.valid?, "the year is outside the range 1970..2970"
      assert_equal \
        "The year 1962 in \"1962-02-23\" is outside the accepted range 1970 to 2970.",
        filter.invalid_reason
    end
  end

  context "fractions of a second" do
    test "it handles them" do
      @quals[:created].must "2020-06-25T03:04:15.345"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert filter.valid?
      assert_nil filter.must_not
      assert_equal({ term: { created: "2020-06-25T03:04:15.345" } }, filter.must)
    end

    test "it handles them with a timezone" do
      @quals[:created].must "2020-06-25T03:04:15.345Z"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert filter.valid?
      assert_nil filter.must_not
      assert_equal({ term: { created: "2020-06-25T03:04:15.345Z" } }, filter.must)
    end

    test "it handles them with a numeric timezone" do
      @quals[:created].must "2020-06-25T03:04:15.345-05:00"
      filter = Search::Filters::DateRangeFilter.new(field: :created, qualifiers: @quals)

      assert filter.valid?
      assert_nil filter.must_not
      assert_equal({ term: { created: "2020-06-25T03:04:15.345-05:00" } }, filter.must)
    end
  end
end
