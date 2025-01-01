# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class RequestorHasActivityTest < GitHub::TestCase
    setup do
      @has_activity = TestableRequestorHasActivity.new
    end

    test "init adds max time range" do
      travel_to "2024-10-01 02:12:34" do
        has_activity = TestableRequestorHasActivity.new
        filters = has_activity.filters
        range_filter = filters.find { |f| f.field == Queries::FilterField::Timestamp }
        assert range_filter
        assert range_filter.is_a?(Queries::RangeFilter)
        assert_equal Time.now, T.cast(range_filter, Queries::RangeFilter).max_value
        assert_equal Time.now - 31.days, T.cast(range_filter, Queries::RangeFilter).value
      end
    end

    test "with_user" do
      @has_activity.with_user(2)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::SubjectId && f.value == 2 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::SubjectType && f.value == "user" }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::SubjectId}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectName}", query_text
    end

    test "with_installation" do
      @has_activity.with_installation(3)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorId && f.value == 3 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorType && f.value == ActorType::Installation.serialize }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::ActorId}", query_text
      assert_match "#{Queries::SummaryKeyField::ActorName}", query_text
    end

    test "with_oauth_app" do
      @has_activity.with_oauth_app(4)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorId && f.value == 4 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorType && f.value == ActorType::OauthApp.serialize }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorName
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::ActorId}", query_text
      assert_match "#{Queries::SummaryKeyField::ActorName}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectId}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectName}", query_text
    end

    test "with_classic_pat" do
      @has_activity.with_classic_pat(5)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorId && f.value == 5 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorType && f.value == ActorType::ClassicPat.serialize }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorName
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::ActorId}", query_text
      assert_match "#{Queries::SummaryKeyField::ActorName}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectId}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectName}", query_text
    end

    test "with_fine_grained_pat" do
      @has_activity.with_fine_grained_pat(6)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorId && f.value == 6 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorType && f.value == ActorType::FineGrainedPat.serialize }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorName
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::ActorId}", query_text
      assert_match "#{Queries::SummaryKeyField::ActorName}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectId}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectName}", query_text
    end

    test "with_github_app_user_to_server" do
      @has_activity.with_github_app_user_to_server(7)
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorId && f.value == 7 }
      assert @has_activity.filters.any? { |f| f.field == Queries::FilterField::ActorType && f.value == ActorType::GithubAppUserToServer.serialize }
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::ActorName
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectId
      assert @has_activity.project_by.include? Queries::SummaryKeyField::SubjectName
      if GitHub.multi_tenant_enterprise?
        @has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
      end
      query_text = @has_activity.query_text
      assert_match "#{Queries::SummaryKeyField::ActorId}", query_text
      assert_match "#{Queries::SummaryKeyField::ActorName}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectId}", query_text
      assert_match "#{Queries::SummaryKeyField::SubjectName}", query_text
    end

    test "raises error if filters are not specified" do
      e = assert_raises Error do
        @has_activity.filters.clear
        @has_activity.query_text
      end
      assert_equal ErrorCode::FILTERS_NOT_SPECIFIED, e.code
    end

    test "raises error if project_by is not specified" do
      e = assert_raises Error do
        @has_activity.query_text
      end
      assert_equal ErrorCode::SUMMARY_FIELDS_NOT_SPECIFIED, e.code
    end

    context "view toggling" do
      test "initialize with secondary tabular input feature flag disabled" do
        GitHub.flipper.disable(:api_insights_use_secondary_tabular_input)

        has_activity = assert_nothing_raised { TestableRequestorHasActivity.new }
        assert_equal GitHub.api_insights_kusto_tabular_input_primary, has_activity.tabular_input
      end

      test "initialize with secondary tabular input feature flag enabled" do
        GitHub.flipper.enable(:api_insights_use_secondary_tabular_input)

        has_activity = assert_nothing_raised { TestableRequestorHasActivity.new }
        assert_equal GitHub.api_insights_kusto_tabular_input_secondary, has_activity.tabular_input

        GitHub.flipper.disable(:api_insights_use_secondary_tabular_input)
      end
    end

    context "in multi-tenant mode" do
      test "without current tenant" do
        GitHub::CurrentTenant.remove

        assert_nil GitHub::CurrentTenant.get
        has_activity = TestableRequestorHasActivity.new
        has_activity.with_user(1)
        assert_raises RuntimeError do
          has_activity.get
        end
      end

      test "with current tenant" do
        refute_nil GitHub::CurrentTenant.get

        now = Time.now.utc
        has_activity = TestableRequestorHasActivity.new
        has_activity.with_user(1)
        has_activity.with_tenant_id(GitHub::CurrentTenant.get.id)
        assert has_activity.filters.any? { |f| f.field == Queries::FilterField::TenantId && f.value == GitHub::CurrentTenant.get.id }
        assert_nothing_raised do
          has_activity.get
        end
      end
    end if TestEnv.test_in_multitenancy_mode?
  end

  class TestableRequestorHasActivity < RequestorHasActivity
    def initialize
      super 1
    end
  end
end
