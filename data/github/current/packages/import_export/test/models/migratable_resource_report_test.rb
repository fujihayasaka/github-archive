# typed: true
# frozen_string_literal: true

require "test_helper"

class MigratableResourceReportTest < GitHub::TestCase
  fixtures do
    @migratable_resource_report = create(:migratable_resource_report)
  end

  test "the factory is valid" do
    assert_valid @migratable_resource_report
  end

  test "it requires a migration" do
    @migratable_resource_report.migration = nil
    refute_valid @migratable_resource_report
  end

  test "it requires a model_type" do
    @migratable_resource_report.model_type = nil
    refute_valid @migratable_resource_report
  end

  test "it requires a total_count" do
    @migratable_resource_report.total_count = nil
    refute_valid @migratable_resource_report
  end

  test "total_count must be a positive number" do
    @migratable_resource_report.total_count = -1
    refute_valid @migratable_resource_report
  end

  test "it requires a success_count" do
    @migratable_resource_report.success_count = nil
    refute_valid @migratable_resource_report
  end

  test "success_count must be a positive number" do
    @migratable_resource_report.success_count = -1
    refute_valid @migratable_resource_report
  end

  test "it requires a failure_count" do
    @migratable_resource_report.failure_count = nil
    refute_valid @migratable_resource_report
  end

  test "failure_count must be a positive number" do
    @migratable_resource_report.failure_count = -1
    refute_valid @migratable_resource_report
  end
end
