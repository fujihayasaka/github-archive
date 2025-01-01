# typed: true
# frozen_string_literal: true

require "test_helper"

class OutlierFilterTest < GitHub::TestCase
  test "handles empty sets" do
    subject = OutlierFilter.new
    assert_equal [], subject.filter([])
  end

  test "filters large values" do
    outlier = 10_000
    values = (0...20).to_a
    values << outlier

    subject = OutlierFilter.new
    filtered = subject.filter(values)

    assert_equal 20, filtered.size
    refute filtered.include?(outlier)
  end
end
