# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Indexable::Processor::ElasticsearchUpdateResponseTest < GitHub::TestCase
  test "#data summarizes a passed in array of hashes" do
    result = klass.new(data: [{ "total" => 1 }, { "total" => "2" }])
    assert_equal 3, result.data["total"]
  end

  test "#data summarizes a passed hash" do
    result = klass.new(data: { "total" => 1 })
    assert_equal 1, result.data["total"]
  end

  test "#data includes raw response data" do
    data = { "total" => 1, "items" => [{ "foo" => "bar" }] }
    expected_result = { "_raw" => [data], "total" => 1 }
    result = klass.new(data:)
    assert_equal expected_result, result.data
  end

  private def klass
    MemexProjectColumn::Indexable::Processor::ElasticsearchUpdateResponse
  end
end
