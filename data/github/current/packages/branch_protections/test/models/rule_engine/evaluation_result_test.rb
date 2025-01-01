# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineEvaluationResultTest < GitHub::TestCase
  setup do
    @metadata = { "hello" => "world" }
    @candidate = RuleEngine::MetadataSources::Types::BlobCandidate.new(oid: "abcdef", commit_oid: "123456", path: "file.txt", size: 1, contents: nil)
  end

  test "constructor" do
    result = RuleEngine::EvaluationResult.new(candidate: @candidate, success: true, metadata: @metadata)
    assert_equal @candidate, result.candidate
    assert result.success?
    assert_equal @metadata, result.metadata
  end

  test "success" do
    result = RuleEngine::EvaluationResult.success(candidate: @candidate, metadata: @metadata)
    assert_equal @candidate, result.candidate
    assert result.success?
    assert_equal @metadata, result.metadata
  end

  test "failure" do
    result = RuleEngine::EvaluationResult.failure(candidate: @candidate, metadata: @metadata)
    assert_equal @candidate, result.candidate
    refute result.success?
    assert_equal @metadata, result.metadata
  end
end
