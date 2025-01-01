# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesAuditLogQueryTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @org    = create(:organization)
    @actor  = create(:user)
    @user   = create(:user)
    @business = create :business, organizations: [@org]
  end

  def assert_actions(exp, response)
    actions = response.results.collect { |h| h["action"] }.sort
    assert_same_elements exp, actions
  end

  test "only returns audit_entry documents" do
    with_es_refresh do
      @entry = log({ action: "team.create", org_id: @org.id, data: { team: "awesome team" } })
    end

    query = build_audit_query(org_id: @org.id)
    response = query.execute

    assert_equal 1, response.total, response.results.inspect
    assert_equal @entry["_id"], response.results.first.id, "audit log action not returned"
  end

  test "orders results by timestamp" do
    with_es_refresh do
      @entry = log action: "team.create", org_id: @org.id, data: { team: "first" }
      @entry = log action: "team.create", org_id: @org.id, data: { team: "last" }
    end

    # Default ordering is DESC
    query = build_audit_query(org_id: @org.id)
    response = query.execute
    assert_equal "last", response.results.first["data"]["team"]

    query = build_audit_query(org_id: @org.id, direction: "ASC")
    response = query.execute
    assert_equal "first", response.results.first["data"]["team"]
  end

  test "when fetching documents with raw_data fields are accessible" do
    with_es_refresh do
      log action: "team.create", org_id: @org.id, raw_data: "{ \"team\": \"first\" }"
    end

    query = build_audit_query(org_id: @org.id)
    response = query.execute
    assert_equal "first", response.results.first["data"]["team"]
  end

  context "determining indexes to query" do
    test "defaults to searching only 3 months of data" do
      range = 4.times.collect { |i| Time.now.utc.end_of_day - i.months }
      query_index = range.collect { |date| date.strftime("#{@audit_log_test_helper_index.name}-%Y-%m") }.join(",")
      query = Search::Queries::AuditLogQuery.new

      assert_equal query_index, query.query_params[:index]
    end

    test "queries all indexes when raw query" do
      query = Search::Queries::AuditLogQuery.new(raw: true)

      assert query.raw?
      assert_equal @audit_log_test_helper_index.name, query.query_params[:index]
    end

    test "respects index_name parameter" do
      index_name = "audit_log-test0-d41d8cd98f00b204e9800998ecf8427e"
      query = Search::Queries::AuditLogQuery.new(index_name: index_name)

      assert_equal index_name, query.query_params[:index]
    end

    test "uses multiple indexes for created filter ranging multiple months" do
      range = 10.times.collect { |i| T.cast((Time.now.utc - i.months), Time) }
      query_index = range.collect { |date| date.strftime("#{@audit_log_test_helper_index.name}-%Y-%m") }.join(",")
      query = Search::Queries::AuditLogQuery.new(phrase: "created:#{T.must(range.last).strftime('%Y-%m-%d')}..#{T.must(range.first).strftime('%Y-%m-%d')}")

      assert_equal query_index, query.query_params[:index]
    end

    test "uses single index for created filter ranging one month" do
      time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]
      # Freeze the time not near a month boundary
      user_time = Time.local(2014, 9, 20, 4, 59, 59) # 2014-09-20 16:59:59 PDT

      # We need to use PDT since Time.zone is UTC by default
      Time.use_zone(time_zone) do
        Timecop.freeze(user_time) do
          range = [Time.zone.now.beginning_of_month, Time.zone.now.end_of_month]
          query_index = range.first.strftime("#{@audit_log_test_helper_index.name}-%Y-%m")
          query = Search::Queries::AuditLogQuery.new(phrase: "created:#{range.first.strftime('%Y-%m-%d')}..#{range.last.strftime('%Y-%m-%d')}")

          assert_equal query_index, query.query_params[:index]
        end
      end
    end

    test "uses single index for specific dates" do
      date = Time.now.utc
      query_index = date.strftime("#{@audit_log_test_helper_index.name}-%Y-%m")
      query = Search::Queries::AuditLogQuery.new(phrase: "created:#{date.strftime('%Y-%m-%d')}")

      assert_equal query_index, query.query_params[:index]
    end

    test "does not exceed max possible entry time" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]

      # The time before UTC will roll over to the next month
      user_time = Time.local(2014, 9, 30, 4, 59, 59) # 2014-09-30 16:59:59 PDT

      Time.use_zone(user_time_zone) do
        Timecop.freeze(user_time) do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:2014-09-01..2015-10-01")

          assert_equal "#{@audit_log_test_helper_index.name}-2014-09", query.query_params[:index]
        end
      end
    end

    test "respects local time zone when generating from and to utc time" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]
      Time.use_zone(user_time_zone) do
        Timecop.freeze do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:2014-10-01")
          assert_equal Time.utc(2014, 10, 1, 7, 0, 0).iso8601, query.from.iso8601
          assert_equal Time.utc(2014, 10, 2, 6, 59, 59).iso8601, query.to.iso8601
          assert_equal user_time_zone.local(2014, 10, 1, 0, 0, 0).iso8601, query.from.in_time_zone(user_time_zone).iso8601
          assert_equal user_time_zone.local(2014, 10, 1, 23, 59, 59).iso8601, query.to.in_time_zone(user_time_zone).iso8601
        end
      end
    end

    test "respects utc time zone when generating from search range for a utc time query with gte range qualifier" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]
      Time.use_zone(user_time_zone) do
        Timecop.freeze do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:>=2014-10-01T10:01:05Z")
          assert_equal Time.utc(2014, 10, 1, 10, 1, 5).iso8601, query.from.iso8601
          assert_equal user_time_zone.local(2014, 10, 1, 3, 1, 5).iso8601, query.from.in_time_zone(user_time_zone).iso8601
        end
      end
    end

    test "respects utc time zone when generating search range for a utc time query with lte range qualifier" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]
      Time.use_zone(user_time_zone) do
        Timecop.freeze do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:<=2014-10-01T10:01:05Z")
          assert_equal Time.utc(2014, 7, 1, 7, 0, 0).iso8601, query.from.iso8601
          assert_equal user_time_zone.local(2014, 7, 1, 0, 0, 0).iso8601, query.from.in_time_zone(user_time_zone).iso8601
          assert_equal Time.utc(2014, 10, 1, 10, 1, 5).iso8601, query.to.iso8601
          assert_equal user_time_zone.local(2014, 10, 1, 3, 1, 5).iso8601, query.to.in_time_zone(user_time_zone).iso8601
        end
      end
    end

    test "when utc time with no qualifiers are given it should return nil to from query ranges" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]
      Time.use_zone(user_time_zone) do
        Timecop.freeze do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:2014-10-01T10:01:05Z")
          assert_nil query.from
          assert_nil query.to
        end
      end
    end

    test "respects local time zone for generating indexes to query" do
      user_time_zone = ActiveSupport::TimeZone["America/Los_Angeles"]

      # The time before UTC will roll over to the next month
      pre_utc_time = user_time_zone.local(2014, 9, 30, 16, 59, 59) # 2014-09-30 16:59:59 PDT

      # The time UTC will roll over to the next month
      post_utc_time = user_time_zone.local(2014, 9, 30, 17, 0, 0) # 2014-09-30 17:00:00 PDT

      Time.use_zone(user_time_zone) do
        Timecop.freeze(pre_utc_time) do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:2014-10-01")

          assert_equal "#{@audit_log_test_helper_index.name}-2014-09", query.query_params[:index]
        end

        Timecop.freeze(post_utc_time) do
          query = Search::Queries::AuditLogQuery.new(phrase: "created:2014-10-01")

          assert_equal "#{@audit_log_test_helper_index.name}-2014-10", query.query_params[:index]
        end
      end
    end
  end

  context "when building query" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @query = Search::Queries::AuditLogQuery.new
    end

    test "ignores unavailable indexes by default" do
      query = Search::Queries::AuditLogQuery.new
      assert query.query_params[:ignore_unavailable]
    end

    test "sets default from and to timestamps" do
      time = Time.now

      Timecop.freeze(time) do
        query = Search::Queries::AuditLogQuery.new

        assert_equal time.utc.end_of_day, query.to
        assert_equal (time.utc.end_of_day - query.query_indexes.months).beginning_of_day, query.from
      end
    end

    test "parses created range" do
      @query.phrase = "created:\"2000-01-01..2001-01-01\""
      assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
      assert_equal "2001-01-01T23:59:59Z", @query.to.iso8601
    end

    test "parses created range with years" do
      @query.phrase = "created:\"2000..2001\""
      assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
      assert_equal "2001-12-31T23:59:59Z", @query.to.iso8601
    end

    test "parses created range with year and day" do
      @query.phrase = "created:\"2000..2001-01-02\""
      assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
      assert_equal "2001-01-02T23:59:59Z", @query.to.iso8601
    end

    test "parses created lte range with specific time" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05:00:00\""
        assert_equal Time.zone.parse("2000-01-01T00:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-30T05:00:00").utc, @query.to
      end
    end

    test "parses created gte range with specific time" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01T05:00:00..2016-10-30\""
        assert_equal Time.zone.parse("2000-01-01T05:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-30T23:59:59").utc.end_of_day, @query.to
      end
    end

    test "parses created lte range with specific month" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10\""
        assert_equal Time.zone.parse("2000-01-01T00:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-31T23:59:59").utc.end_of_day, @query.to
      end
    end

    test "parses created lte range with specific hour" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05\""
        assert_equal Time.zone.parse("2000-01-01T00:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-30T05:59:59").utc.end_of_hour, @query.to
      end
    end

    test "parses created lte range with specific minute" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05:10\""
        assert_equal Time.zone.parse("2000-01-01T00:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-30T05:10:59").utc, @query.to
      end
    end

    test "parses created range without time specified" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30\""
        assert_equal Time.zone.parse("2000-01-01T00:00:00").utc, @query.from
        assert_equal Time.zone.parse("2016-10-30T23:59:59").utc.end_of_day, @query.to
      end
    end

    test "parses created range with wildcard lte" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..*\""
        assert_equal Time.zone.parse("2000-01-01").utc, @query.from
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses created range with wildcard gte" do
      @query.phrase = "created:\"*..2001-01-01\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-01").end_of_day.utc, @query.to
    end

    test "parses YYYY created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2000\""
        assert_equal Time.zone.parse("2001-01-01T00:00:00.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01\""
        assert_equal Time.zone.parse("2001-02-01T00:00:00.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DD created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01\""
        assert_equal Time.zone.parse("2001-01-02T00:00:00.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13\""
        assert_equal Time.zone.parse("2001-01-01T14:00:00.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH:MM created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13:45\""
        assert_equal Time.zone.parse("2001-01-01T13:46:00.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH:MM:SS created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13:45:34\""
        assert_equal Time.zone.parse("2001-01-01T13:45:35.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH:MM:SS.MMM created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13:45:34.341\""
        assert_equal Time.zone.parse("2001-01-01T13:45:34.342Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH:MM:SSZ created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13:45:34Z\""
        assert_equal Time.zone.parse("2001-01-01T13:45:35.000Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY-MM-DDTHH:MM:SS.MMMZ created date with gt modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">2001-01-01T13:45:34.341Z\""
        assert_equal Time.zone.parse("2001-01-01T13:45:34.342Z").utc.iso8601(3), @query.from.iso8601(3)
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses YYYY created date with lt modifier" do
      @query.phrase = "created:\"<2001\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2000-12-31").utc.end_of_year.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM created date with lt modifier" do
      @query.phrase = "created:\"<2001-01\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2000-12-31").utc.end_of_month.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DD created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-01").utc.end_of_day.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-02T02:59:59Z").utc.end_of_hour.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH:MM created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03:23\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal (Time.zone.parse("2001-01-02T03:22").utc + 1.minute - 1.second).iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH:MM:SS created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03:23:45\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-02T03:23:44").utc.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH:MM:SSZ created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03:23:45Z\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-02T03:23:44").utc.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH:MM:SS.MMM created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03:23:45.678\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-02T03:23:45.677").utc.iso8601(3), @query.to.iso8601(3)
    end

    test "parses YYYY-MM-DDTHH:MM:SS.MMMZ created date with lt modifier" do
      @query.phrase = "created:\"<2001-01-02T03:23:45.678Z\""
      assert_equal (@query.to - @query.query_indexes.months).beginning_of_day, @query.from
      assert_equal Time.zone.parse("2001-01-02T03:23:45.677").utc.iso8601(3), @query.to.iso8601(3)
    end

    test "parses created date with gte modifier" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\">=2000-01-01\""
        assert_equal Time.zone.parse("2000-01-01").utc, @query.from
        assert_equal time.end_of_day.utc, @query.to
      end
    end

    test "parses created date with decimal value" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05:10:50.543\""
        assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
        assert_equal "2016-10-30T05:10:50.543Z", @query.to.iso8601(3)
      end
    end

    test "parses created date with decimal value and Z timezone" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05:10:50.543Z\""
        assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
        assert_equal "2016-10-30T05:10:50.543Z", @query.to.iso8601(3)
      end
    end

    test "parses created date with decimal value and timezone offset" do
      time = Time.zone.now
      Timecop.freeze(time) do
        @query.phrase = "created:\"2000-01-01..2016-10-30T05:05:50.543-05:00\""
        assert_equal "2000-01-01T00:00:00Z", @query.from.iso8601
        assert_equal "2016-10-30T10:05:50.543Z", @query.to.iso8601(3)
      end
    end

    test "parses created range with lte modifier" do
      @query.phrase = "created:\"<=2001-01-01\""

      assert_equal Time.zone.parse("2000-10-01T00:00:00").utc, @query.from
      assert_equal Time.zone.parse("2001-01-01T23:59:59").utc.end_of_day, @query.to
    end

    test "parses created non-range date" do
      @query.phrase = "created:2001-01-01"

      assert_equal Time.zone.parse("2001-01-01 00:00:00").utc, @query.from
      assert_equal Time.zone.parse("2001-01-01 23:59:59").utc.end_of_day, @query.to
    end

    test "parses multiple created filters" do
      @query.phrase = "created:>=2019-04-01 created:<=2019-04-05"
      assert_equal "2019-04-01T00:00:00Z", @query.from.iso8601
      assert_equal "2019-04-05T23:59:59Z", @query.to.iso8601
    end

    test "can build raw query" do
      @query.raw = true

      assert @query.raw?
    end

    test "can parse subject as actor when user" do
      @query = Search::Queries::AuditLogQuery.new(subject: @user)

      assert_predicate @query, :user?
      refute_predicate @query, :organization?
      refute_predicate @query, :business?
    end

    test "can parse subject as actor when organization" do
      @query = Search::Queries::AuditLogQuery.new(subject: @org)

      assert_predicate @query, :organization?
      refute_predicate @query, :user?
      refute_predicate @query, :business?
    end

    test "can parse subject as actor when business" do
      @query = Search::Queries::AuditLogQuery.new(subject: @business)

      assert_predicate @query, :business?
      refute_predicate @query, :organization?
      refute_predicate @query, :user?
    end

    test "can determine that querying by IP is allowed when user querying their own audit log" do
      @query = Search::Queries::AuditLogQuery.new(actor_id: @user.id, current_user: @user)
      assert_predicate @query, :can_query_by_ip?
    end

    test "can determine that querying by IP is not allowed when user querying a different audit log" do
      @query = Search::Queries::AuditLogQuery.new(actor_id: @org.id, current_user: @user)
      refute_predicate @query, :can_query_by_ip?
    end

    unless GitHub.enterprise?
      test "can determine that querying by IP is allowed for a business with IP disclosure enabled" do
        @business.enable_source_ip_disclosure(actor: @business.owners.first)
        @query = Search::Queries::AuditLogQuery.new(subject: @business)
        assert_predicate @query, :can_query_by_ip?
      end

      test "can determine that querying by IP is not allowed for a business with IP disclosure disabled" do
        @business.disable_source_ip_disclosure(actor: @business.owners.first)
        @query = Search::Queries::AuditLogQuery.new(subject: @business)
        refute_predicate @query, :can_query_by_ip?
      end
    end

    test "can't parse subject when not a valid subject" do
      assert_raises(ArgumentError) do
        Search::Queries::AuditLogQuery.new(subject: {})
      end
    end

    test "can build count query" do
      refute @query.count_query?

      @query = build_audit_query(search_type: "count")
      assert @query.count_query?
    end

    test "includes filter for invalid documents" do
      qs = @query.build_query
      expected = { term: { "data._invalid" => true } }
      assert_equal expected, qs.dig(:bool, :filter, :bool, :must_not)
    end

    context "with search qualifiers" do
      test "generates an actor filter" do
        @query.phrase = "actor:dewski actor:Caged"

        qs = @query.build_query
        expected = { terms: { actor: %w[dewski Caged] } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates an action filter" do
        query = Search::Queries::AuditLogQuery.new(allowlist: ["team.create", "team.destroy"])
        query.phrase = "action:team.create action:team.destroy"

        qs = query.build_query
        expected = {
          terms: {
            action: ["team.create", "team.destroy"],
          },
        }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates a user filter" do
        @query.phrase = "user:dewski user:Caged"

        qs = @query.build_query
        expected = { terms: { user: %w[dewski Caged] } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates a operation_type filter" do
        @query.phrase = "operation:create"

        qs = @query.build_query
        expected = { term: { operation_type: "create" } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates a country_code filter" do
        @query.phrase = "country:US"

        qs = @query.build_query
        expected = { term: { "actor_location.country_code" => "US" } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "normalizes country code input" do
        @query.phrase = "country:us"

        qs = @query.build_query
        expected = { term: { "actor_location.country_code" => "US" } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates a country_name filter" do
        @query.phrase = "country:\"United States\""

        qs = @query.build_query
        expected = { term: { "actor_location.country_name" => "United States" } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates a repo filter" do
        @query.phrase = "repo:github/github repo:github/hire"

        qs = @query.build_query
        expected = { terms: { repo: ["github/github", "github/hire"] } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end

      test "generates an org filter" do
        @query.phrase = "org:darcy-the-dog"

        qs = @query.build_query
        expected = { term: { org: "darcy-the-dog" } }

        assert_includes qs.dig(:bool, :filter, :bool, :must), expected
      end
    end

    context "with context" do
      context "for business" do
        test "builds nested bool filter" do
          business_context_query = Search::Queries::AuditLogQuery.new(business_id: @business.id)
          actions = business_context_query.allowlist - business_context_query.denylist
          from = business_context_query.from
          to = business_context_query.to
          expected = {
            bool: {
              must: { match_all: {} },
              filter: {
                bool: {
                  must: [
                    { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                    { terms: { action: actions } },
                  ],
                  must_not: { term: { "data._invalid" => true } },
                  should: { term: { business_id: @business.id } },
                  minimum_should_match: 1,
                },
              },
            },
          }

          assert_equal expected, business_context_query.build_query
        end
      end

      context "for organization" do
        setup do # rubocop:disable GitHub/NestedSetupTeardown
          @org_context_query = Search::Queries::AuditLogQuery.new(org_id: @org.id, user_id: @org.id)
        end

        test "builds nested bool filter" do
          actions = @org_context_query.allowlist - @org_context_query.denylist
          from = @org_context_query.from
          to = @org_context_query.to
          expected = {
            bool: {
              must: { match_all: {} },
              filter: {
                bool: {
                  must: [
                    { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                    { terms: { action: actions } },
                  ],
                  must_not: { term: { "data._invalid" => true } },
                  should: [
                    { term: { user_id: @org.id } },
                    { term: { org_id: @org.id } },
                  ],
                  minimum_should_match: 1,
                },
              },
            },
          }

          assert_equal expected, @org_context_query.build_query
        end
      end

      context "for user" do
        setup do # rubocop:disable GitHub/NestedSetupTeardown
          @user_context_query = Search::Queries::AuditLogQuery.new(user_id: @user.id, actor_id: @user.id)
        end

        test "builds nested bool filter" do
          actions = @user_context_query.allowlist - @user_context_query.denylist
          from = @user_context_query.from
          to = @user_context_query.to
          expected = {
            bool: {
              must: { match_all: {} },
              filter: {
                bool: {
                  must: [
                    { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                    { terms: { action: actions } },
                  ],
                  must_not: { term: { "data._invalid" => true } },
                  should: [
                    { term: { user_id: @user.id } },
                    { term: { actor_id: @user.id } },
                  ],
                  minimum_should_match: 1,
                },
              },
            },
          }

          assert_equal expected, @user_context_query.build_query
        end
      end
    end

    context "for user" do
      setup do # rubocop:disable GitHub/NestedSetupTeardown
        @user_query = Search::Queries::AuditLogQuery.new(user_id: @user.id)
      end

      test "is user query" do
        assert @user_query.user?
        refute @user_query.organization?
      end

      test "empty queries filter what users have permission to" do
        actions = @user_query.allowlist
        from = @user_query.from
        to = @user_query.to

        expected = {
          bool: {
            must: { match_all: {} },
            filter: {
              bool: {
                must: [
                  { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                  { terms: { action: actions } },
                ],
                must_not: { term: { "data._invalid" => true } },
                should: { term: { user_id: @user.id } },
                minimum_should_match: 1,
              },
            },
          },
        }

        assert_equal expected, @user_query.build_query
      end
    end

    context "for actor" do
      setup do # rubocop:disable GitHub/NestedSetupTeardown
        @actor_query = Search::Queries::AuditLogQuery.new(actor_id: @actor.id)
      end

      test "is user query" do
        assert @actor_query.user?
        refute @actor_query.organization?
      end

      test "empty queries filter what actors have permission to" do
        actions = @actor_query.allowlist
        from = @actor_query.from
        to = @actor_query.to

        expected = {
          bool: {
            must: { match_all: {} },
            filter: {
              bool: {
                must: [
                  { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                  { terms: { action: actions } },
                ],
                must_not: { term: { "data._invalid" => true } },
                should: { term: { actor_id: @actor.id } },
                minimum_should_match: 1,
              },
            },
          },
        }

        assert_same_hash expected, @actor_query.build_query
      end
    end

    context "for org" do
      setup do # rubocop:disable GitHub/NestedSetupTeardown
        @org_query = Search::Queries::AuditLogQuery.new(org_id: @org.id)
      end

      test "is organization query" do
        assert @org_query.organization?
        refute @org_query.user?
      end

      test "empty queries filter what organizations have permission to" do
        actions = @org_query.allowlist - @org_query.denylist
        from = @org_query.from
        to = @org_query.to

        expected = {
          bool: {
            must: { match_all: {} },
            filter: {
              bool: {
                must: [
                  { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                  { terms: { action: actions } },
                ],
                must_not: { term: { "data._invalid" => true } },
                should: { term: { org_id: @org.id } },
                minimum_should_match: 1,
              },
            },
          },
        }

        assert_equal expected, @org_query.build_query
      end
    end

    context "for business" do
      test "is business query" do
        business_query = Search::Queries::AuditLogQuery.new(business_id: @business.id)
        assert business_query.business?
        refute business_query.organization?
        refute business_query.user?
      end

      test "empty queries filter what business has permission to" do
        business_query = Search::Queries::AuditLogQuery.new(business_id: @business.id)
        actions = business_query.allowlist - business_query.denylist
        from = business_query.from
        to = business_query.to

        expected = {
          bool: {
            must: { match_all: {} },
            filter: {
              bool: {
                must: [
                  { range: { :@timestamp => { gte: from.iso8601(3), lte: to.iso8601(3) } } },
                  { terms: { action: actions } },
                ],
                must_not: { term: { "data._invalid" => true } },
                should: { term: { business_id: @business.id } },
                minimum_should_match: 1,
              },
            },
          },
        }

        assert_equal expected, business_query.build_query
      end
    end
  end

  context "when executing the query" do
    test "does not return invalid results" do
      with_es_refresh do
        log action: "user.add_email", actor_id: @user.id, data: { _invalid: true }
      end

      query = build_audit_query(actor_id: @user.id, allowlist: ["user.add_email"])
      response = query.execute

      assert_equal 0, response.total
    end

    test "can filter results on action prefix" do
      with_es_refresh do
        log action: "user.create", actor_id: @user.id
        log action: "user.destroy", actor_id: @user.id
      end

      query = build_audit_query(phrase: "action:user", allowlist: ["user.create"])
      assert query.valid_query?

      response = query.execute
      assert_actions ["user.create"], response
    end

    test "with user context" do
      with_es_refresh do
        log action: "oauth.create", user_id: @user.id
        log action: "oauth.destroy", actor_id: @user.id
        log action: "security.breach", user_id: @user.id
      end

      query = build_audit_query(
        user_id: @user.id,
        actor_id: @user.id,
        allowlist: ["oauth.create", "oauth.destroy"],
        denylist: ["security.breach"],
      )
      response = query.execute

      assert_equal 2, response.total, response.results.inspect
      assert_actions ["oauth.create", "oauth.destroy"], response
    end

    test "returns empty results for far back date range" do
      query = build_audit_query(phrase: "created:1991-09-14..1992-09-14", index_name: nil)
      assert query.valid_query?

      response = query.execute
      assert_equal 0, response.total
    end

    test "returns empty results for invalid dates" do
      query = build_audit_query(phrase: "created:1991-13", index_name: nil)
      refute query.valid_query?

      response = query.execute
      assert_equal 0, response.total
    end

    test "with org context" do
      with_es_refresh do
        log action: "org.create", org_id: @org.id
        log action: "org.destroy", user_id: @org.id
        log action: "user.create", org_id: @org.id
      end

      query = build_audit_query(
        org_id: @org.id,
        user_id: @org.id,
        allowlist: ["org.create", "org.destroy"],
        denylist: ["user.create"],
      )
      response = query.execute

      assert_equal 2, response.total, response.results.inspect
      assert_actions ["org.create", "org.destroy"], response
    end

    test "with business context" do
      with_es_refresh do
        log action: "business.create", business_id: @business.id
        log action: "business.add_organization", business_id: @business.id
        log action: "user.create", user_id: @user.id
      end

      query = build_audit_query(
        business_id: @business.id,
        allowlist: ["business.create", "business.add_organization"],
        denylist: ["user.create"],
      )
      response = query.execute

      assert_equal 2, response.total, response.results.inspect
      assert_actions ["business.create", "business.add_organization"], response
    end

    test "only returns entries with action in allowlist" do
      with_es_refresh do
        log action: "oauth.login"
        log action: "oauth_access.create"
        log action: "security.breach"
      end

      query = build_audit_query(
        allowlist: ["oauth.login"],
        denylist: ["oauth_access.create", "security.breach"],
      )
      response = query.execute

      assert_equal 1, response.total, response.results.inspect
      assert_actions ["oauth.login"], response
    end

    test "excludes entries with action in denylist" do
      with_es_refresh do
        log action: "ldap.login"
        log action: "ldap.sync"
        log action: "ldap.delete"
        log action: "security.breach"
      end

      query = build_audit_query(
        phrase: "action:ldap.delete",
        allowlist: ["ldap.login", "ldap.delete"],
        denylist: ["ldap.sync", "security.breach"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.delete"], response
    end

    test "returns empty results when searching denylisted term" do
      with_es_refresh do
        log action: "ldap.login"
        log action: "ldap.sync"
        log action: "ldap.delete"
        log action: "security.breach"
      end

      query = build_audit_query(
        phrase: "action:ldap.delete",
        allowlist: ["ldap.login", "ldap.sync"],
        denylist: ["ldap.delete", "security.breach"],
      )
      response = query.execute

      refute query.valid_query?
      assert_nil query.invalid_reason
      assert_equal 0, response.total
    end

    test "returns allowlisted entries when negating explicit denylisted term" do
      with_es_refresh do
        log action: "org.add_member"
        log action: "org.remove_member"
        log action: "org.transfer"
      end

      query = build_audit_query(
        phrase: "-action:org.transfer -action:org.add_member",
        allowlist: ["org.add_member", "org.remove_member"],
        denylist: ["org.transfer"],
      )
      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.total
      assert_actions ["org.remove_member"], response
    end

    test "returns allowlisted entries when negating allowlist term" do
      with_es_refresh do
        log action: "team.add_member", actor_location: { country_code: "US" }
        log action: "team.remove_member", actor_location: { country_code: "CA" }
        log action: "oauth_access.create", actor_location: { country_code: "GB" }
        log action: "user.two_factor_authenticated", actor_location: { country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "-action:team.add_member",
        allowlist: ["team.add_member", "team.remove_member"],
        denylist: ["oauth_access.create", "user.two_factor_authenticated"],
      )
      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.size
      assert_equal 1, response.total
      assert_actions ["team.remove_member"], response
    end

    test "returns allowlisted entries when negating allowlist term with a prefix" do
      with_es_refresh do
        log action: "team.add_member", actor_location: { country_code: "US" }
        log action: "team.remove_member", actor_location: { country_code: "CA" }
        log action: "oauth_access.create", actor_location: { country_code: "GB" }
      end

      query = build_audit_query(
        phrase: "-action:team",
        allowlist: ["team.add_member", "team.remove_member", "oauth_access.create"],
      )

      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.size
      assert_actions ["oauth_access.create"], response
    end

    test "does not leak information when allowlist and denylist have common term" do
      with_es_refresh do
        log action: "repo.disable_discussions", actor_location: { country_code: "US" }
        log action: "repo.enable_discussions", actor_location: { country_code: "CA" }
        log action: "repo.create", actor_location: { country_code: "GB" }
      end

      query = build_audit_query(
        allowlist: ["repo.create"],
        denylist: ["repo.enable_discussions", "repo.disable_discussions"],
      )
      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.size
      assert_equal 1, response.total
      assert_actions ["repo.create"], response

      query = build_audit_query(
        phrase: "-action:repo.enable_discussions",
        allowlist: ["repo.create"],
        denylist: ["repo.enable_discussions", "repo.disable_discussions"],
      )
      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.size
      assert_equal 1, response.total
      assert_actions ["repo.create"], response
    end

    test "can fetch specific actions when negating denylisted terms exist" do
      with_es_refresh do
        log action: "org.add_member"
        log action: "org.update_member"
        log action: "org.remove_member"
        log action: "org.transfer"
      end

      query = build_audit_query(
        phrase: "action:org.update_member -action:org.transfer -action:org.add_member",
        allowlist: ["org.add_member", "org.update_member", "org.remove_member"],
        denylist: ["org.transfer"],
      )
      response = query.execute

      assert query.valid_query?
      assert_equal 1, response.total
      assert_actions ["org.update_member"], response
    end

    test "terms are extracted into must filter" do
      with_es_refresh do
        log action: "ldap.login", org_id: 1
        log action: "ldap.login", org_id: 2
      end

      query = build_audit_query(
        org_id: 1,
        allowlist: ["ldap.login"],
      )
      response = query.execute

      assert_equal 1, response.total
      hit = response.results.first
      assert_equal 1, hit["org_id"]
    end

    test "can filter multiple fields" do
      with_es_refresh do
        log action: "ldap.login"
        log action: "ldap.sync"
        log action: "ssh.create"
      end

      query = build_audit_query(
        phrase: "action:ldap.login action:ssh.create",
        allowlist: ["ldap.login", "ldap.sync", "ssh.create"],
      )
      response = query.execute

      assert_equal 2, response.total
      assert_actions ["ldap.login", "ssh.create"], response
    end

    test "can negate fields" do
      with_es_refresh do
        log action: "ldap.login"
        log action: "ldap.sync"
        log action: "ssh.create"
      end

      query = build_audit_query(
        phrase: "-action:ssh.create",
        allowlist: ["ldap.login", "ldap.sync", "ssh.create"],
      )
      response = query.execute

      assert_equal 2, response.total
      assert_actions ["ldap.login", "ldap.sync"], response
    end

    test "can filter results from user supplied query" do
      with_es_refresh do
        log action: "ssh.create"
        log action: "ldap.login"
      end

      query = build_audit_query(
        phrase: "action:ssh.create",
        allowlist: ["ldap.login", "ssh.create"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ssh.create"], response
    end

    test "can sort entries by country name" do
      with_es_refresh do
        log action: "ldap.login", actor_location: { country_name: "United States", country_code: "US" }
        log action: "ldap.logout", actor_location: { country_name: "Australia", country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "country:\"United States\"",
        allowlist: ["ldap.login", "ldap.logout"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.login"], response
    end

    test "can sort entries by country code" do
      with_es_refresh do
        log action: "ldap.login", actor_location: { country_name: "United States", country_code: "US" }
        log action: "ldap.logout", actor_location: { country_name: "Australia", country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "country:AU",
        allowlist: ["ldap.login", "ldap.logout"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.logout"], response
    end

    test "can sort entries by lowercase country code" do
      with_es_refresh do
        log action: "ldap.login", actor_location: { country_name: "United States", country_code: "US" }
        log action: "ldap.logout", actor_location: { country_name: "Australia", country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "country:au",
        allowlist: ["ldap.login", "ldap.logout"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.logout"], response
    end

    test "can exclude entries by country name" do
      with_es_refresh do
        log action: "ldap.login", actor_location: { country_name: "United States", country_code: "US" }
        log action: "ldap.logout", actor_location: { country_name: "Australia", country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "-country:\"United States\"",
        allowlist: ["ldap.login", "ldap.logout"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.logout"], response
    end

    test "can exclude entries by country code" do
      with_es_refresh do
        log action: "ldap.login", actor_location: { country_name: "United States", country_code: "US" }
        log action: "ldap.logout", actor_location: { country_name: "Australia", country_code: "AU" }
      end

      query = build_audit_query(
        phrase: "-country:AU",
        allowlist: ["ldap.login", "ldap.logout"],
      )
      response = query.execute

      assert_equal 1, response.total
      assert_actions ["ldap.login"], response
    end

    if GitHub.enterprise?
      test "Ignores git events by default" do
        with_es_refresh do
          log action: "org.create", org_id: @org.id
          log action: "git.clone", org_id: @org.id
        end

        query = build_audit_query(
          org_id: @org.id,
        )
        assert_equal ["git.fetch", "git.clone", "git.push"], query.denylist
        response = query.execute

        assert_equal 1, response.total, response.results.inspect
        assert_actions ["org.create"], response
      end

      test "Ignores git events when events_type is web" do
        with_es_refresh do
          log action: "org.create", org_id: @org.id
          log action: "git.clone", org_id: @org.id
        end

        query = build_audit_query(
          org_id: @org.id,
          events_type: :web,
        )
        assert_equal ["git.fetch", "git.clone", "git.push"], query.denylist
        response = query.execute

        assert_equal 1, response.total, response.results.inspect
        assert_actions ["org.create"], response
      end

      test "includes git events when events_type is 'all'" do
        with_es_refresh do
          log action: "org.create", org_id: @org.id
          log action: "git.clone", org_id: @org.id
        end

        query = build_audit_query(
          org_id: @org.id,
          events_type: :all,
        )
        response = query.execute

        assert_equal [], query.denylist
        assert_equal 2, response.total, response.results.inspect
        assert_actions ["org.create", "git.clone"], response
      end

      test "includes only git events when events_type is 'git'" do
        with_es_refresh do
          log action: "org.create", org_id: @org.id
          log action: "git.clone", org_id: @org.id
        end

        query = build_audit_query(
          org_id: @org.id,
          events_type: :git,
        )
        response = query.execute

        assert_equal [], query.denylist
        assert_equal 1, response.total, response.results.inspect
        assert_actions ["git.clone"], response
      end

      test "allows searching by hashed_token" do
        owner = create(:user)
        other_owner = create(:user)
        @business.add_owner(other_owner, actor: @business.owners.first)
        @business.add_owner(owner, actor: @business.owners.first)
        access = create(:oauth_access, user: other_owner)
        access2 = create(:oauth_access, user: owner)

        access_token = access.reset_token
        token_hash = Digest::SHA256.base64digest(access_token)

        access_token2 = access2.reset_token
        token_hash2 = Digest::SHA256.base64digest(access_token2)

        with_es_refresh do
          log action: "api.request", data: { hashed_token: token_hash }, business_id: @business.id
          log action: "api.request", data: { hashed_token: token_hash2 }, business_id: @business.id
        end

        query = build_audit_query(
          phrase: "hashed_token:#{token_hash}",
        )

        response = query.execute
        assert(response.length > 0)

        response.each do |match|
          assert_equal token_hash, match[:data][:hashed_token]
        end
      end

      test "allows searching by token_id" do
        owner = create(:user)
        other_owner = create(:user)
        @business.add_owner(other_owner, actor: @business.owners.first)
        @business.add_owner(owner, actor: @business.owners.first)
        access = create(:oauth_access, user: other_owner)
        access2 = create(:oauth_access, user: owner)

        with_es_refresh do
          log action: "repo.create", data: { token_id: access.id }, business_id: @business.id
          log action: "repo.create", data: { token_id: access2.id }, business_id: @business.id
        end

        query = build_audit_query(
          phrase: "token_id:#{access.id}",
        )

        response = query.execute
        assert(response.length > 0)

        response.each do |match|
          assert_equal access.id, match[:data][:token_id]
        end
      end

      test "allows searching by org" do
        with_es_refresh do
          log action: "repo.create", org: "darcy-the-menace"
          log action: "repo.create", org: "darcy-the-angel"
        end

        query = build_audit_query(
          phrase: "org:darcy-the-menace"
        )

        response = query.execute

        assert_equal 1, response.total, response.results.inspect
        assert_actions ["repo.create"], response
        assert_equal "darcy-the-menace", response.results.first[:org]
      end
    end
  end

  context "when querying with limited history" do
    test "queries outside of the limit only query the last index possible" do
      Timecop.freeze(2019, 5, 5) do # Cinco de Mayo
        restricted_query = Search::Queries::AuditLogQuery.new(phrase: "created:2013..2016", limit_history: true)
        expected_index = "#{@audit_log_test_helper_index.name}-2019-02"
        assert_equal expected_index, restricted_query.query_params[:index]
      end
    end

    test "queries crossing the limit are restricted to the current index and n-number of indices" do
      Timecop.freeze(2019, 5, 5) do
        restricted_query = Search::Queries::AuditLogQuery.new(phrase: "created:>2018-10-01", limit_history: true)
        expected_indices = %w[2019-05 2019-04 2019-03 2019-02].map { |s| "#{@audit_log_test_helper_index.name}-#{s}" }.join(",")
        assert_equal expected_indices, restricted_query.query_params[:index]
      end
    end
  end

  context "#allowlist" do
    test "returns business allowlist AND user allowlist when business_id is present" do
      query = Search::Queries::AuditLogQuery.new(business_id: @business.id)
      allowlist = if GitHub.single_business_environment?
        AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names
      else
        AuditLogEntry.business_cloud_action_names
      end

      assert_equal query.allowlist.count, query.allowlist.uniq.count
      assert_equal allowlist, query.allowlist
    end

    test "returns business allowlist with api when business_id AND from-api is present" do
      query = Search::Queries::AuditLogQuery.new(business_id: @business.id, from_api: true)
      allowlist = if GitHub.single_business_environment?
        AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names
      else
        AuditLogEntry.business_cloud_action_names
      end
      expected = (allowlist + AuditLogEntry.business_api_only_action_names).uniq
      assert_equal query.allowlist.count, query.allowlist.uniq.count
      assert_equal expected, query.allowlist
    end

    test "returns organization allowlist when org_id is present" do
      query = Search::Queries::AuditLogQuery.new(org_id: @org.id, user_id: @user.id)

      assert_equal AuditLogEntry.organization_action_names, query.allowlist
    end

    test "returns organization only api-only allowlist from api" do
      query = Search::Queries::AuditLogQuery.new(org_id: @org.id, user_id: @user.id, from_api: true)

      expected = AuditLogEntry.organization_action_names + AuditLogEntry.organization_api_only_action_names
      assert_equal expected, query.allowlist
    end

    test "returns user allowlist when user_id is present" do
      query = Search::Queries::AuditLogQuery.new(user_id: @user.id, actor_id: @user.id)

      assert_equal AuditLogEntry.user_action_names, query.allowlist
    end

    if GitHub.enterprise?
      test "returns enterprise allowlist AND user allowlist otherwise" do
        query = Search::Queries::AuditLogQuery.new
        expected = AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names
        assert_includes query.allowlist, "business.add_admin" # business.add_admin is from AuditLogEntry.business_server_action_names
        assert_includes query.allowlist, "account.billing_date_change" # account.billing_date_change is from AuditLogEntry.user_action_names
        assert_equal query.allowlist.count, query.allowlist.uniq.count
        assert_equal expected, query.allowlist
      end

      test "returns enterprise allowlist AND user allowlist AND from-api are present" do
        query = Search::Queries::AuditLogQuery.new(from_api: true)
        expected = ((AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names) + AuditLogEntry.business_api_only_action_names).uniq

        assert_includes query.allowlist, "business.add_admin"
        assert_includes query.allowlist, "account.billing_date_change"
        assert_includes query.allowlist, "workflows.created_workflow_run" # account.billing_date_change is from AuditLogEntry.business_api_only_action_names
        assert_equal query.allowlist.count, query.allowlist.uniq.count
        assert_equal expected, query.allowlist
      end
    end
  end

  context "#denylist" do
    if GitHub.enterprise?
      test "returns a denylist appended with the git prefix" do
        query = Search::Queries::AuditLogQuery.new

        assert_equal ["git.fetch", "git.clone", "git.push"], query.denylist
      end

      test "returns default denylist when events_type is :all" do
        query = Search::Queries::AuditLogQuery.new(events_type: :all)
        expected = []
        assert_equal expected, query.denylist
      end

      test "returns default denylist when events_type is :git" do
        query = Search::Queries::AuditLogQuery.new(events_type: :git)
        expected = []
        assert_equal expected, query.denylist
      end

      test "returns git event denylist when events_type is :web" do
        query = Search::Queries::AuditLogQuery.new(events_type: :web)
        expected = ["git.fetch", "git.clone", "git.push"]
        assert_equal expected, query.denylist
      end
    end
  end
end
