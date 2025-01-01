# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class UserStatsTest < GitHub::TestCase
    def setup
      @user_id = 123
      @user_stats = TestableUserStats.new @user_id
    end

    test "should initialize UserStats with correct filters and summary key fields" do
      @user_stats.query.filters.any? { |f| f.field == Queries::FilterField::SubjectId && f.value == @user_id }
      @user_stats.query.filters.any? { |f| f.field == Queries::FilterField::SubjectType && f.value == "user" }

      summary_key_fields = @user_stats.query.summary_key_fields
      assert_includes summary_key_fields, Queries::SummaryKeyField::ActorType
      assert_includes summary_key_fields, Queries::SummaryKeyField::ActorId
      assert_includes summary_key_fields, Queries::SummaryKeyField::ActorName
      assert_includes summary_key_fields, Queries::SummaryKeyField::IntegrationId
      assert_includes summary_key_fields, Queries::SummaryKeyField::OauthApplicationId
    end

    test "should add actor name prefix filter with with_actor_name_prefix method" do
      actor_name_prefix = "John"
      @user_stats.with_actor_name_prefix(actor_name_prefix)

      filters = @user_stats.query.filters
      actor_name_filter = filters.find { |f| f.field == Queries::FilterField::ActorName }
      refute_nil actor_name_filter
      assert_equal actor_name_prefix, actor_name_filter.value
      assert_equal "startswith", actor_name_filter.operator
    end

    test "should validate sort field correctly" do
      valid_sort_field = Queries::SortField::ActorName
      invalid_sort_field = Queries::SortField::SubjectName

      assert @user_stats.send(:valid_sort_field?, valid_sort_field)
      assert_not @user_stats.send(:valid_sort_field?, invalid_sort_field)
    end

    test "with_actor_type adds filter" do
      actor_type = ActorType::FineGrainedPat

      user_stats = TestableUserStats.new(1).with_actor_type(actor_type)

      filter = user_stats.query.filters.find { |f| f.field == Queries::FilterField::ActorType }
      refute_nil filter
      assert_equal actor_type.serialize, filter.value
    end
  end

  class TestableUserStats < UserStats
    def initialize(user_id)
      now = Time.now.utc
      super 1, now - 1.day, now, user_id
    end

    def query
      super
    end
  end
end
