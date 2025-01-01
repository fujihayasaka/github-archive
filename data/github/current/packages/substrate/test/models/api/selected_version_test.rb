# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiSelectedVersionTest < GitHub::TestCase
  test "it returns the version" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    selected = Api::SelectedVersion.new(requested_version, version, Api::SelectedVersion::REASON_DEFAULT)
    assert_equal selected.version, version
  end

  test "it returns the reason" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_REQUEST_HEADER
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert_equal selected.reason, reason
  end

  test "test skipped predicate is true if reason is skipped" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_SKIPPED
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert selected.skipped?
  end

  test "pinned predicate is true if reason is skipped" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_PINNED
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert selected.pinned?
  end

  test "invalid predicate is true if reason is invalid" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_INVALID
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert selected.invalid?
  end

  test "default predicate is true if reason is default" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_DEFAULT
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert selected.default?
  end

  test "request header predicate is true if reason is request_header" do
    version = "10/10/2010"
    requested_version = "10/10/2010"
    reason = Api::SelectedVersion::REASON_REQUEST_HEADER
    selected = Api::SelectedVersion.new(requested_version, version, reason)
    assert selected.request_header?
  end
end
