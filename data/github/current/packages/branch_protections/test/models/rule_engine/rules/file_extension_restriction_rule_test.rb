# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesFileExtensionRestrictionRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)

    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["*.bad"]
      }
    )

    @rule = T::let(RuleEngine::Rules::FileExtensionRestrictionRule.new, RuleEngine::Rules::FileExtensionRestrictionRule)
  end

  test "succeeds when file extension not restricted" do
    candidate = create_blob_candidate(path: "text.md")
    assert_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "text.bad.md")
    assert_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "some/path/text.bad.md")
    assert_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "path/text.bad.md")
    assert_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?
  end

  test "fails when file extension restricted" do
    candidate = create_blob_candidate(path: "text.bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "text.exe.bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "path/text.bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: ".path/text.bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "path/.path/text.Bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?
  end

  test "ignores case when checking file extension" do
    candidate = create_blob_candidate(path: "text.Bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "some/path/text.Bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "path/text.Bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    candidate = create_blob_candidate(path: "path/text.Bad.exe")
    assert_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?

    @rule_config.parameters["restricted_file_extensions"] = ["*.Bad"]

    candidate = create_blob_candidate(path: "text.bad")
    refute_predicate @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate), :success?
  end

  test "generates allowed rule run when no violations" do
    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, [])

    assert_predicate result, :allowed?
  end

  test "generates failed rule run when violations exist" do
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate(path: "text.bad"))]
    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)
    assert_predicate result, :failed?

    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate(path: "text.exe.bad"))]
    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)
    assert_predicate result, :failed?
  end

  test "valid with one file extension" do
    errors = @rule.validate_parameterized(@rule_config)
    puts errors
    refute errors.any?
  end

  test "valid with no file extensions" do
    no_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => []
      }
    )
    errors = @rule.validate_parameterized(no_file_extension_rule_config)
    refute errors.any?
  end

  test "errors when restricted file extensions is nil" do
    nil_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => nil
      }
    )
    errors = @rule.validate_parameterized(nil_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :unexpected_type, error[:error_code]
    assert_equal "Expected array, got NilClass", error[:message]
  end

  test "errors when restricted file extension is empty string" do
    empty_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["*.exe", "  "]
      }
    )
    errors = @rule.validate_parameterized(empty_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :empty_extension, error[:error_code]
    assert_equal "File extension cannot be empty", error[:message]
  end

  test "errors when restricted file extension doesn't start with *." do
    no_star_dot_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["exe"]
      }
    )
    errors = @rule.validate_parameterized(no_star_dot_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :invalid_extension, error[:error_code]
    assert_equal "File extension must start with *.", error[:message]
  end

  test "errors when restricted file extension contains backslash" do
    backslash_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["*.\\exe"]
      }
    )
    errors = @rule.validate_parameterized(backslash_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :invalid_extension, error[:error_code]
    assert_equal "File extension cannot contain \\, /, or *", error[:message]
  end

  test "errors when restricted file extension contains forward slash" do
    forward_slash_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["*./exe"]
      }
    )
    errors = @rule.validate_parameterized(forward_slash_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :invalid_extension, error[:error_code]
    assert_equal "File extension cannot contain \\, /, or *", error[:message]
  end

  test "errors when restricted file extension contains wildcard" do
    wildcard_file_extension_rule_config = build(
      :repository_rule_configuration,
      rule_type: "file_extension_restriction",
      parameters: {
        "restricted_file_extensions" => ["*.*exe"]
      }
    )
    errors = @rule.validate_parameterized(wildcard_file_extension_rule_config)
    assert errors.any?
    error = errors.first[:sub_errors].first
    assert_equal :invalid_extension, error[:error_code]
    assert_equal "File extension cannot contain \\, /, or *", error[:message]
  end
end
