# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusCheckConfig::StatusTest < GitHub::TestCase
  test "a pending status will return correct values for state helpers" do
    status_config = StatusCheckConfig::Status.new(state: StatusCheckConfig::States::PENDING)
    assert      status_config.pending?
    assert_not  status_config.success?
    assert_not  status_config.failure?
    assert_not  status_config.incomplete?
  end

  test "a success status will return correct values for state helpers" do
    status_config = StatusCheckConfig::Status.new(state: StatusCheckConfig::States::SUCCESS)
    assert      status_config.success?
    assert_not  status_config.pending?
    assert_not  status_config.failure?
    assert_not  status_config.incomplete?
  end

  test "a failure status will return correct values for state helpers" do
    status_config = StatusCheckConfig::Status.new(state: StatusCheckConfig::States::FAILURE)
    assert      status_config.failure?
    assert_not  status_config.pending?
    assert_not  status_config.success?
    assert_not  status_config.incomplete?
  end

  test "a incomplete status will return correct values for state helpers" do
    status_config = StatusCheckConfig::Status.new(state: StatusCheckConfig::States::INCOMPLETE)
    assert      status_config.incomplete?
    assert_not  status_config.pending?
    assert_not  status_config.success?
    assert_not  status_config.failure?
  end
end
