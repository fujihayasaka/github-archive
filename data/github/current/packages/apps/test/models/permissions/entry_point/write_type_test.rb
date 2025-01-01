# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsEntryPointWriteTypeTest < GitHub::TestCase
  test "values match EntryPoint metric suffixes" do
    expected = Permissions::Service::EntryPoint::METRIC_SUFFIXES
    actual = Permissions::EntryPoint::WriteType.values.map(&:serialize)

    assert_same_elements expected, actual
  end
end
