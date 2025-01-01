# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class SubjectStatsTest < GitHub::TestCase
    setup do
      @subject_stats = TestableSubjectStats.new
    end

    test "initialization adds additional summary key fields" do
      assert_includes @subject_stats.query.summary_key_fields, Queries::SummaryKeyField::SubjectType
      assert_includes @subject_stats.query.summary_key_fields, Queries::SummaryKeyField::SubjectId
      assert_includes @subject_stats.query.summary_key_fields, Queries::SummaryKeyField::SubjectName
      assert_includes @subject_stats.query.summary_key_fields, Queries::SummaryKeyField::IntegrationIdWhenSubjectInstallation
    end

    test "with_subject_name_prefix adds filter" do
      subject_name_prefix = "easy-"

      @subject_stats.with_subject_name_prefix(subject_name_prefix)

      filter = @subject_stats.query.filters.find { |f| f.field == Queries::FilterField::SubjectName }
      refute_nil filter
      assert_equal subject_name_prefix, filter.value
      assert_equal "startswith", filter.operator
    end

    test "with_subject_type adds filter" do
      subject_type = SubjectType::User

      summary_stats = TestableSubjectStats.new.with_subject_type(subject_type)

      filter = summary_stats.query.filters.find { |f| f.field == Queries::FilterField::SubjectType }
      refute_nil filter
      assert_equal subject_type.serialize, filter.value
    end
  end

  class TestableSubjectStats < SubjectStats
    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
