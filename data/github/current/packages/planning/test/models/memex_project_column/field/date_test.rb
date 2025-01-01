# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnDateTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user = create(:verified_user)
    @memex = create(:memex_project)
    @present_day_item = create(:memex_project_item, memex_project: @memex)
    @date_field = create(:memex_project_column, data_type: :date, name: "Key Date", memex_project: @memex).to_field
    @date_value = create(:date_memex_project_column_value, value: "1985-10-26", memex_project_item: @present_day_item, column: @date_field)

    @back_then_item = create(:memex_project_item, memex_project: @memex)
    @back_then_date_value = create(:date_memex_project_column_value, value: "1955-11-12", memex_project_item: @back_then_item, column: @date_field)

    @the_future_item = create(:memex_project_item, memex_project: @memex)
    @the_future_date_value = create(:date_memex_project_column_value, value: "2015-10-21", memex_project_item: @the_future_item, column: @date_field)
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct date configuration" do
      assert_equal(
        {
          type: "date",
          format: "strict_date_optional_time",
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
        },
        @date_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads date data" do
      @date_field.preload_elasticsearch_document_data([@present_day_item])
      assert_no_queries { @date_field.elasticsearch_document(@present_day_item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the date value" do
      refute_nil @date_value.value

      assert_equal(
        @date_value.value,
        @date_field.elasticsearch_document(@present_day_item)
      )
    end

    test "returns nil when no date is set" do
      @date_value.destroy!
      assert_nil @date_field.elasticsearch_document(@present_day_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "returns an arbitrary date" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      refute_nil Date.iso8601(@date_field.seed_elasticsearch_document(context))
    end
  end

  context "#execute" do
    test "returns all results if no query is specified" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 3, response.total
      assert_same_elements([@back_then_item.id, @present_day_item.id, @the_future_item.id], response_database_ids)
    end

    test "returns undated results when using `no:` filter" do
      undated_item = create(:memex_project_item, memex_project: @memex)

      populate_elasticsearch_index!([undated_item, @back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:#{@date_field.query_slug}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 1, response.total
      assert_same_elements([undated_item.id], response_database_ids)
    end

    test "returns matching results for a query matching a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:1985-10-26",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 1, response.total
      assert_same_elements [@present_day_item.id], response_database_ids
    end

    test "returns matching results for a query excluding a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-#{@date_field.query_slug}:1985-10-26",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, response.total
      assert_same_elements [@back_then_item.id, @the_future_item.id], response_database_ids
    end

    test "replaces `@today` with today's date" do
      today = Time.zone.now.freeze
      today_item = new_item_with_date(today.to_date.to_s)

      populate_elasticsearch_index!([today_item])

      Timecop.freeze(today) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [today_item.id], response_database_ids
      end
    end

    test "replaces `@today` with today's date even if it appears multiple times" do
      today = Time.zone.now.freeze
      today_item = new_item_with_date(today.to_date.to_s)

      populate_elasticsearch_index!([today_item])

      Timecop.freeze(today) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today..@today",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [today_item.id], response_database_ids
      end
    end

    test "replaces `@today` with today's date and understands what today is in the viewer's timezone" do
      halloween_utc = Time.utc(2023, 10, 31, 0, 0, 1)
      halloween_item = new_item_with_date(halloween_utc.to_date.to_s)

      user_in_australia = create(:verified_user, time_zone: ActiveSupport::TimeZone["Australia/Sydney"])
      user_in_los_angeles = create(:verified_user, time_zone: ActiveSupport::TimeZone["America/Los_Angeles"])

      populate_elasticsearch_index!([halloween_item])

      Timecop.freeze(halloween_utc) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: user_in_australia, # It is Halloween in Australia
          query: "#{@date_field.query_slug}:@today",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [halloween_item.id], response_database_ids

        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: user_in_los_angeles, # It is October 30 in Los Angeles
          query: "#{@date_field.query_slug}:@today",
        ).execute

        assert_equal 0, response.total
      end
    end

    test "returns matching results for a `@today` keyword with addition" do
      september_26_1985 = Time.utc(1985, 9, 26, 0, 0, 0)
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      Timecop.freeze(september_26_1985) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today+30",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [@present_day_item.id], response_database_ids
      end
    end

    test "returns matching results for a `@today` keyword with subtraction" do
      november_25_1985 = Time.utc(1985, 11, 25, 0, 0, 0)
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      Timecop.freeze(november_25_1985) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today-30",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [@present_day_item.id], response_database_ids
      end
    end

    test "returns matching results for a `@today` keyword with addition and subtraction" do
      june_18_2005 = Time.utc(2005, 6, 18, 0, 0, 0)

      june_1_item  = new_item_with_date("2005-06-01")
      june_13_item = new_item_with_date("2005-06-13")
      june_18_item = new_item_with_date(june_18_2005.to_date.to_s)
      june_21_item = new_item_with_date("2005-06-21")
      june_30_item = new_item_with_date("2005-06-30")

      populate_elasticsearch_index!([june_1_item, june_13_item, june_18_item, june_21_item, june_30_item])
      Timecop.freeze(june_18_2005) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today-10..@today+10",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 3, response.total
        assert_same_elements [june_13_item.id, june_18_item.id, june_21_item.id], response_database_ids
      end
    end

    test "returns matching results for a query greater than a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:>1985-10-26",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 1, response.total
      assert_same_elements([@the_future_item.id], response_database_ids)
    end

    test "returns matching results for a query greater than @today" do
      october_26_1985 = Time.utc(1985, 10, 26, 12, 0, 0)
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])

      Timecop.freeze(october_26_1985) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:>@today",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements([@the_future_item.id], response_database_ids)
      end
    end

    test "returns matching results for a query greater than or equal (both >= and n..*) to a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      greater_than_response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:>=1985-10-26",
      ).execute

      greater_than_response_database_ids = greater_than_response.results.map { |r| r["_source"]["database_id"] }
      assert_equal 2, greater_than_response.total
      assert_same_elements [@present_day_item.id, @the_future_item.id], greater_than_response_database_ids

      open_range_response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:1985-10-26..*",
      ).execute

      open_range_response_database_ids = open_range_response.results.map { |r| r["_source"]["database_id"] }
      assert_equal 2, open_range_response.total
      assert_same_elements [@present_day_item.id, @the_future_item.id], open_range_response_database_ids

      assert_equal greater_than_response.results, open_range_response.results, "The results for 'key-date:>=1985-10-26' should be the same as 'key-date:1985-10-26..*'"
    end

    test "returns matching results for a query greater than or equal to (both >= and n..*) @today" do
      october_26_1985 = Time.utc(1985, 10, 26, 12, 0, 0)

      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])

      Timecop.freeze(october_26_1985) do
        greater_than_response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:>=@today",
        ).execute

        greater_than_response_database_ids = greater_than_response.results.map { |r| r["_source"]["database_id"] }
        assert_equal 2, greater_than_response.total
        assert_same_elements [@present_day_item.id, @the_future_item.id], greater_than_response_database_ids

        open_range_response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:@today..*",
        ).execute

        open_range_response_database_ids = open_range_response.results.map { |r| r["_source"]["database_id"] }
        assert_equal 2, open_range_response.total
        assert_same_elements [@present_day_item.id, @the_future_item.id], open_range_response_database_ids

        assert_equal greater_than_response.results, open_range_response.results, "The results for 'key-date:>=@today' should be the same as 'key-date:@today..*'"
      end
    end

    test "returns matching results for a query less than a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:<1985-10-26",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 1, response.total
      assert_same_elements [@back_then_item.id], response_database_ids
    end

    test "returns matching results for a query less than @today" do
      october_26_1985 = Time.utc(1985, 10, 26, 12, 0, 0)

      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      Timecop.freeze(october_26_1985) do
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:<@today",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [@back_then_item.id], response_database_ids
      end
    end

    test "returns matching results for a query less than or equal to (both <= and *..n) a date" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      less_than_response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:<=1985-10-26",
      ).execute

      less_than_response_database_ids = less_than_response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, less_than_response.total
      assert_same_elements [@back_then_item.id, @present_day_item.id], less_than_response_database_ids

      open_range_response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:*..1985-10-26",
      ).execute

      open_range_response_database_ids = open_range_response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, open_range_response.total
      assert_same_elements [@back_then_item.id, @present_day_item.id], open_range_response_database_ids

      assert_equal less_than_response.results, open_range_response.results, "The results for 'key-date:<=1985-10-26' should be the same as 'key-date:*..1985-10-26'"
    end

    test "returns matching results for a query less than or equal to (both <= and *..n) @today" do
      october_26_1985 = Time.utc(1985, 10, 26, 12, 0, 0)

      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      Timecop.freeze(october_26_1985) do
        less_than_response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:<=@today",
        ).execute

        less_than_response_database_ids = less_than_response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 2, less_than_response.total
        assert_same_elements [@back_then_item.id, @present_day_item.id], less_than_response_database_ids

        open_range_response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@date_field.query_slug}:*..@today",
        ).execute

        open_range_response_database_ids = open_range_response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 2, open_range_response.total
        assert_same_elements [@back_then_item.id, @present_day_item.id], open_range_response_database_ids

        assert_equal less_than_response.results, open_range_response.results, "The results for 'key-date:<=@today' should be the same as 'key-date:*..@today'"
      end
    end

    test "returns matching results for a closed range query" do
      populate_elasticsearch_index!([@back_then_item, @present_day_item, @the_future_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@date_field.query_slug}:1982-04-25..2023-10-25",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, response.total
      assert_same_elements [@present_day_item.id, @the_future_item.id], response_database_ids
    end
  end

  def new_item_with_date(date_value)
    item = create(:memex_project_item, memex_project: @memex)
    create(:date_memex_project_column_value, memex_project_item: item, column: @date_field, value: date_value)
    item
  end

  context "sorting by date" do
    test "ascending order" do
      date_1, date_2, date_3 = %w[2021-02-01 2021-02-10 2022-02-01]

      items = [
        new_item_with_date(date_2),
        new_item_with_date(date_1),
        new_item_with_date(date_3)
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [@date_field.sort_fragment(direction: "asc")]
      ).execute

      expected_asc_order = [date_str_to_ms(date_1), date_str_to_ms(date_2), date_str_to_ms(date_3)]
      actual_asc_order   = response.results.map do |i|
        i["sort"].first
      end

      assert_equal expected_asc_order, actual_asc_order
    end
  end

  test "descending order" do
    date_1, date_2, date_3 = %w[2021-02-01 2021-02-10 2022-02-01]

    items = [
      new_item_with_date(date_2),
      new_item_with_date(date_1),
      new_item_with_date(date_3)
    ]

    populate_elasticsearch_index!(items)

    response = Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
      query: "",
      sort: [@date_field.sort_fragment(direction: "desc")]
    ).execute

    expected_desc_order = [date_str_to_ms(date_3), date_str_to_ms(date_2), date_str_to_ms(date_1)]
    actual_desc_order   = response.results.map do |i|
      i["sort"].first
    end

    assert_equal expected_desc_order, actual_desc_order
  end

  test "no sorting" do
    date_1, date_2, date_3 = %w[2021-02-01 2021-02-10 2022-02-01]

    items = [
      new_item_with_date(date_2),
      new_item_with_date(date_1),
      new_item_with_date(date_3)
    ]

    populate_elasticsearch_index!(items)

    response = Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
      query: "",
    ).execute

    asc_order    = [date_str_to_ms(date_1), date_str_to_ms(date_2), date_str_to_ms(date_3)]
    desc_order   = [date_str_to_ms(date_3), date_str_to_ms(date_2), date_str_to_ms(date_1)]
    actual_order = response.results.map do |i|
      i["sort"].first
    end

    refute_equal asc_order, actual_order, "Expected unsorted results, got sorted results - test may be flaky."
    refute_equal desc_order, actual_order, "Expected unsorted results, got sorted results - test may be flaky."
  end

  context "#graphql_value" do
    test "null returns null" do
      assert_nil @date_field.graphql_value(nil)
    end

    test "_noValue returns null" do
      assert_nil @date_field.graphql_value("_noValue")
    end

    test "blank string returns null" do
      assert_nil @date_field.graphql_value(nil)
    end

    test "string returns a parsed Date object" do
      june_18_2005 = Time.utc(2005, 6, 18, 0, 0, 0)
      stored_value = (june_18_2005.to_f * 1000).to_i.to_s

      assert_equal june_18_2005.to_date, @date_field.graphql_value(stored_value)
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@date_field.name}", @date_field.graphql_title(nil)
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@date_field.name}", @date_field.graphql_title("_noValue")
    end

    test "empty string returns default empty group title" do
      assert_equal "No #{@date_field.name}", @date_field.graphql_title("")
    end

    test "formats present value" do
      june_18_2005 = Time.utc(2005, 6, 18, 0, 0, 0)
      stored_value = (june_18_2005.to_f * 1000).to_i.to_s

      assert_equal "Jun 18, 2005", @date_field.graphql_title(stored_value)
    end
  end
end
