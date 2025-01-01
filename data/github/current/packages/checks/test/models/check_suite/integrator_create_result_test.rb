# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuiteIntegrationCreateResultTest < GitHub::TestCase
  test "accessors" do
    cs = create :check_suite
    assert CheckSuite::IntegratorCreateResult.new(cs, existing: true).existing?

    refute CheckSuite::IntegratorCreateResult.new(cs).existing?
    assert CheckSuite::IntegratorCreateResult.new(cs, existing: true).success?
  end

  test "stays unchanged even if record mutates" do
    to_mutate = create(:check_suite)
    to_mutate.head_sha = nil
    to_mutate.save

    invalid_result = CheckSuite::IntegratorCreateResult.new(to_mutate)
    refute_empty to_mutate.errors.messages, "expected record to be invalid on create due to missing sha"
    refute_predicate invalid_result, :success?, "expected result to be invalid on create due to missing sha"

    to_mutate.head_sha = "aabb"
    to_mutate.save
    assert_empty to_mutate.errors.messages
    refute_predicate invalid_result, :success?, "expected result not to mutate along with record"
  end
end
