# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectElasticsearchConsistencyTest < GitHub::TestCase

  fixtures do
    @project = create(:memex_project)
  end

  def get_consistency_record(memex_project_id = @project.id)
    MemexProjectElasticsearchConsistency.find_or_initialize_by(memex_project_id:)
  end

  test "creates a new record" do
    consistency_record = get_consistency_record
    consistency_record.update(repair_started_at: Time.now, repair_finished_at: Time.now, evaluated_at: Time.now, consistency: 0.5)
    assert consistency_record.persisted?
    assert_equal @project.id, consistency_record.memex_project_id
  end

  test "finds and updates an existing record" do
    consistency_record = get_consistency_record
    consistency_record.update(evaluated_at: Time.now, consistency: 0.5)
    repair_started_at = Time.now
    consistency_record = get_consistency_record
    consistency_record.update(repair_started_at:)
    assert_same_time repair_started_at, consistency_record.repair_started_at
    assert_equal 1, MemexProjectElasticsearchConsistency.count
  end

  test "calculates consistency score" do
    actual_consistency_score = MemexProjectElasticsearchConsistency.consistency_score(inconsistent_count: 75, total_count: 100)

    assert_equal 0.25, actual_consistency_score
  end

  test "calculates consistency score when inconsistent_count and total_count are 0" do
    actual_consistency_score = MemexProjectElasticsearchConsistency.consistency_score(
      inconsistent_count: 0,
      total_count: 0,
    )

    assert_equal 1.0, actual_consistency_score
  end

  test "calculates consistency score when inconsistent_count is 0" do
    actual_consistency_score = MemexProjectElasticsearchConsistency.consistency_score(
      inconsistent_count: 0,
      total_count: 50,
    )

    assert_equal 1.0, actual_consistency_score
  end

  test "raises ArgumentError when inconsistent_count has positive value but total_count is zero" do
    assert_raises ArgumentError do
      MemexProjectElasticsearchConsistency.consistency_score(inconsistent_count: 1, total_count: 0)
    end
  end
end
