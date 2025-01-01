# typed: true
# frozen_string_literal: true

require "test_helper"

class DirectDataAccessTest < GitHub::TestCase
  test "generates correct KQL when no dates are provided" do
    query = Copilot::Metrics::Queries::DirectDataAccess.new(enterprise_id: 42, since_date: nil, until_date: nil)

    Timecop.freeze(Time.new(2025, 1, 1, 1, 0, 0)) do
      expected_kql = <<~KQL
        DDE_ExecutedExports
          | where business_id == 42
          | where target_date >= datetime('#{(Time.now.utc.beginning_of_day - 1.day).iso8601}')
          | extend has_activity = array_length(metadata) > 0
          | extend expanded_metadata = iff(has_activity, metadata, pack_array(bag_pack("Path", "")))
          | mv-expand singlemetadata = expanded_metadata
          | project business_id, business_name, target_date, export_date, uri = singlemetadata["Path"], has_activity
          | summarize uris = make_list_if(uri, uri != "") by business_id, business_name, target_date, export_date
          | order by target_date desc
      KQL
      assert_without_whitespace(expected_kql, query.get_reports)
    end
  end

  test "generates correct KQL when since date is provided" do
    Timecop.freeze(Time.new(2025, 1, 1, 1, 0, 0)) do
      query = Copilot::Metrics::Queries::DirectDataAccess.new(enterprise_id: 42, since_date: 7.days.ago, until_date: nil)
      expected_kql = <<~KQL
        DDE_ExecutedExports
          | where business_id == 42
          | where target_date >= datetime('#{7.days.ago.utc.iso8601}')
          | extend has_activity = array_length(metadata) > 0
          | extend expanded_metadata = iff(has_activity, metadata, pack_array(bag_pack("Path", "")))
          | mv-expand singlemetadata = expanded_metadata
          | project business_id, business_name, target_date, export_date, uri = singlemetadata["Path"], has_activity
          | summarize uris = make_list_if(uri, uri != "") by business_id, business_name, target_date, export_date
          | order by target_date desc
      KQL
      assert_without_whitespace(expected_kql, query.get_reports)
    end
  end

  test "generates correct KQL when until date is provided" do
    Timecop.freeze(Time.new(2025, 1, 1, 1, 0, 0)) do
      query = Copilot::Metrics::Queries::DirectDataAccess.new(enterprise_id: 42, since_date: nil, until_date: 7.days.ago)
      expected_kql = <<~KQL
        DDE_ExecutedExports
          | where business_id == 42
          | where target_date <= datetime('#{7.days.ago.utc.iso8601}')
          | extend has_activity = array_length(metadata) > 0
          | extend expanded_metadata = iff(has_activity, metadata, pack_array(bag_pack("Path", "")))
          | mv-expand singlemetadata = expanded_metadata
          | project business_id, business_name, target_date, export_date, uri = singlemetadata["Path"], has_activity
          | summarize uris = make_list_if(uri, uri != "") by business_id, business_name, target_date, export_date
          | order by target_date desc
      KQL
      assert_without_whitespace(expected_kql, query.get_reports)
    end
  end

  test "generates correct KQL when both dates are provided" do
    Timecop.freeze(Time.new(2025, 1, 1, 1, 0, 0)) do
      query = Copilot::Metrics::Queries::DirectDataAccess.new(enterprise_id: 42, since_date: 14.days.ago, until_date: 7.days.ago)
      expected_kql = <<~KQL
        DDE_ExecutedExports
          | where business_id == 42
          | where target_date between (datetime('#{14.days.ago.utc.iso8601}') .. datetime('#{7.days.ago.utc.iso8601}'))
          | extend has_activity = array_length(metadata) > 0
          | extend expanded_metadata = iff(has_activity, metadata, pack_array(bag_pack("Path", "")))
          | mv-expand singlemetadata = expanded_metadata
          | project business_id, business_name, target_date, export_date, uri = singlemetadata["Path"], has_activity
          | summarize uris = make_list_if(uri, uri != "") by business_id, business_name, target_date, export_date
          | order by target_date desc
      KQL
      assert_without_whitespace(expected_kql, query.get_reports)
    end
  end

  private def assert_without_whitespace(expected, actual)
    assert_equal expected.gsub(/\s+/, ""), actual.gsub(/\s+/, "")
  end
end
