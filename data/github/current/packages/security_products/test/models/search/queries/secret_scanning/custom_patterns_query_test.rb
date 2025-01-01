# typed: true
# frozen_string_literal: true
require "test_helper"

class SearchQueriesCustomPatternsQueryTest < GitHub::TestCase
  test "should return default sort_enum if the query does not have one" do
    q = create_query("")
    assert_equal GitHub::Proto::SecretScanning::Api::V3::SortOrder::CREATED_DESCENDING, q.sort_enum
  end

  test "should return the sort enum based on the slug" do
    q = create_query("sort:created-asc")
    assert_equal GitHub::Proto::SecretScanning::Api::V3::SortOrder::CREATED_ASCENDING, q.sort_enum
  end

  test "should return the first sort enum if there are two" do
    q = create_query("sort:created-asc,created-desc")
    assert_equal GitHub::Proto::SecretScanning::Api::V3::SortOrder::CREATED_ASCENDING, q.sort_enum
  end

  test "should be set to the default query if empty string or null is passed in" do
    q = create_query("")
    assert_equal "is:published,unpublished", q.query

    q = create_query(nil)
    assert_equal "is:published,unpublished", q.query
  end

  test "has_default_is_values? should return true if the query has published and unpublished" do
    q = create_query("")
    assert q.has_default_is_values?

    q = create_query("is:published,unpublished")
    assert q.has_default_is_values?

    q = create_query("is:unpublished,published")
    assert q.has_default_is_values?

    q = create_query(nil)
    assert q.has_default_is_values?

    q = create_query("sort:created-asc, is:published,unpublished")
    assert q.has_default_is_values?

    q = create_query("sort:created-asc")
    assert q.has_default_is_values?
    assert_equal "created-asc", q.sort
  end

  test "has_default_is_values? should return false if the query does not contain both published and unpublisheed" do
    q = create_query("is:published")
    refute q.has_default_is_values?

    q = create_query("is:unpublished")
    refute q.has_default_is_values?

    q = create_query("sort:created-asc, is:unpublished")
    refute q.has_default_is_values?
  end

  test "should return status enums based on 'is'" do
    q = create_query("is:published,unpublished")
    statuses = q.status_enum
    assert statuses.include? GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::PUBLISHED
    assert statuses.include? GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::UNPUBLISHED
    assert_equal 2, statuses.length

    q = create_query("is:published")
    statuses = q.status_enum
    assert statuses.include? GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::PUBLISHED
    refute statuses.include? GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::UNPUBLISHED
    assert_equal 1, statuses.length

    q = create_query("is:published,invalid")
    statuses = q.status_enum
    assert statuses.include? GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::PUBLISHED
    assert_equal 1, statuses.length
  end

  test "should return push protection filter enums based on 'push_protection'" do
    q = create_query("push-protection:include-all")
    assert_equal q.push_protected_filter_enum, GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::INCLUDE_ALL

    q = create_query("push-protection:enabled")
    assert_equal q.push_protected_filter_enum, GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::PUSH_PROTECTED

    q = create_query("push-protection:disabled")
    assert_equal q.push_protected_filter_enum, GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::NOT_PUSH_PROTECTED
  end

  def create_query(query)
    Search::Queries::SecretScanning::CustomPatternsQuery.new(query: query)
  end
end
