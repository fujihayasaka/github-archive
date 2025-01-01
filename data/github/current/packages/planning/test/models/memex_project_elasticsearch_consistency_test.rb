# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectElasticsearchConsistencyTest < GitHub::TestCase

  fixtures do
    @project = create(:memex_project)
  end

  test "creates a new record" do
    consistency_record = MemexProjectElasticsearchConsistency.create_or_update(@project.id, repair_started_at: Time.now, repair_finished_at: Time.now, evaluated_at: Time.now, consistency: 0.5)
    assert consistency_record.persisted?
    assert_equal @project.id, consistency_record.memex_project_id
  end

  test "finds and updates an existing record" do
    MemexProjectElasticsearchConsistency.create_or_update(@project.id, evaluated_at: Time.now, consistency: 0.5)
    repair_started_at = Time.now
    consistency_record = MemexProjectElasticsearchConsistency.create_or_update(@project.id, repair_started_at: Time.now)
    assert_same_time repair_started_at, consistency_record.repair_started_at
    assert_equal 1, MemexProjectElasticsearchConsistency.count
  end

  test "compacts arguments so that nil values don't overwrite non-nil values" do
    MemexProjectElasticsearchConsistency.create_or_update(@project.id, repair_started_at: Time.now, repair_finished_at: Time.now, evaluated_at: Time.now, consistency: 0.5)
    consistency_record = MemexProjectElasticsearchConsistency.create_or_update(@project.id, repair_finished_at: nil)
    assert consistency_record.consistency
    assert consistency_record.repair_started_at
    assert consistency_record.repair_finished_at
  end

  test "calculates consistency score" do
    actual_consistency_score = MemexProjectElasticsearchConsistency.consistency_score(reconciled_count: 75, total_count: 100)

    assert_equal 0.25, actual_consistency_score
  end

  test "does not calculate consistency score when total count is not positive" do
    actual_consistency_score = MemexProjectElasticsearchConsistency.consistency_score(reconciled_count: 1, total_count: 0)

    assert_nil actual_consistency_score
  end
end
