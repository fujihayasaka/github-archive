# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class StatsBaseTest < GitHub::TestCase
    fixtures do
      create(:business)
      create(:organization)
      create(:user)
    end

    setup do
      now = Time.now.utc
      @stats = FakeStats.new 1, now - 1.day, now
    end

    test "initialize valid" do
      now = Time.now.utc
      organization_id = 1
      min_timestamp = now - 1.day
      max_timestamp = now

      stats = assert_nothing_raised { FakeStats.new(organization_id, min_timestamp, max_timestamp) }
      assert stats.query.filters.any? { |f| f.field == Queries::FilterField::OrganizationId && f.value == organization_id }

      range_filter = stats.query.filters.find { |f| f.field == Queries::FilterField::Timestamp }
      refute_nil range_filter
      assert_equal min_timestamp, range_filter.value
      assert_equal max_timestamp, range_filter.max_value
    end

    test "initialize invalid timestamp range negative" do
      now = Time.now.utc
      error = assert_raises(Error) { FakeStats.new(1, now, now - 1.day) }
      assert_equal ErrorCode::TIMESTAMP_RANGE_NEGATIVE, error.code
    end

    test "initialize invalid timestamp range too large" do
      now = Time.now.utc
      error = assert_raises(Error) { FakeStats.new(1, now - 32.days, now) }
      assert_equal ErrorCode::TIMESTAMP_RANGE_TOO_LARGE, error.code
    end

    test "validate sort definitions valid" do
      sort_definitions = [Queries::SortDefinition.new(Queries::SortField::TotalRequestCount)]
      assert_nothing_raised { @stats.validate_sort_definitions(sort_definitions) }
    end

    test "validate sort definitions invalid" do
      sort_definitions = [Queries::SortDefinition.new(Queries::SortField::ActorId)]
      assert_raises(Error) { @stats.validate_sort_definitions(sort_definitions) }
    end

    test "valid sort field" do
      assert @stats.valid_sort_field?(Queries::SortField::TotalRequestCount)
      refute @stats.valid_sort_field?(Queries::SortField::ActorId)
    end

    context "view toggling" do
      test "initialize with secondary tabular input feature flag disabled" do
        disable_feature_flag(:api_insights_use_secondary_tabular_input)

        now = Time.now.utc
        organization_id = 1
        min_timestamp = now - 1.day
        max_timestamp = now

        stats = assert_nothing_raised { FakeStats.new(organization_id, min_timestamp, max_timestamp) }
        assert_equal GitHub.api_insights_kusto_tabular_input_primary, stats.query.tabular_input
      end

      test "initialize with secondary tabular input feature flag enabled" do
        enable_feature_flag(:api_insights_use_secondary_tabular_input)

        now = Time.now.utc
        organization_id = 1
        min_timestamp = now - 1.day
        max_timestamp = now

        stats = assert_nothing_raised { FakeStats.new(organization_id, min_timestamp, max_timestamp) }
        assert_equal GitHub.api_insights_kusto_tabular_input_secondary, stats.query.tabular_input

        disable_feature_flag(:api_insights_use_secondary_tabular_input)
      end
    end

    context "in multi-tenant mode" do
      test "without current tenant" do
        GitHub::CurrentTenant.remove

        assert_nil GitHub::CurrentTenant.get
        assert_raises RuntimeError do
          now = Time.now.utc
          FakeStats.new(1, now - 1.day, now).get
        end
      end

      test "with current tenant" do
        refute_nil GitHub::CurrentTenant.get

        now = Time.now.utc
        fake_stats = FakeStats.new(1, now - 1.day, now)
        fake_stats.with_tenant_id(GitHub::CurrentTenant.get.id)
        assert fake_stats.query.filters.any? { |f| f.field == Queries::FilterField::TenantId && f.value == GitHub::CurrentTenant.get.id }
        assert_nothing_raised do
          fake_stats.get
        end
      end
    end if TestEnv.test_in_multitenancy_mode?
  end

  class FakeStats < StatsBase
    def query
      super
    end

    def validate_sort_definitions(sort_definitions)
      super sort_definitions
    end

    def valid_sort_field?(sort_field)
      super sort_field
    end
  end
end
