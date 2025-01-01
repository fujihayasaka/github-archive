# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesFilePathRestrictionRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
    @root = {
      "ruleset_source" => @repo
    }
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)
    @rule_config = build_file_path_restriction_rule_config([".github/*"])
    @rule = RuleEngine::Rules::FilePathRestrictionRule.new
  end

  def build_file_path_restriction_rule_config(paths)
    build(
      :repository_rule_configuration,
      rule_type: "file_path_restriction",
      parameters: {
        "restricted_file_paths" => paths
      }
    )
  end

  context "#ensure_valid_path_patterns" do
    test "valid if at least one file path is provided" do
      errors = @rule.validate_parameterized(@rule_config, root: @root)
      refute errors.any?
    end

    test "valid if no file paths are given" do
      rule_config = build_file_path_restriction_rule_config([])
      errors = @rule.validate_parameterized(rule_config, root: @root)
      refute errors.any?
    end

    test "returns error if nil" do
      rule_config = build_file_path_restriction_rule_config(nil)
      errors = @rule.validate_parameterized(rule_config, root: @root)
      assert errors.any?
      error = errors.first[:sub_errors].first
      assert_equal :unexpected_type, error[:error_code]
      assert_equal "Expected array, got NilClass", error[:message]
    end

    test "returns error if a file path is an empty string" do
      @rule_config.parameters["restricted_file_paths"] << "   "
      errors = @rule.validate_parameterized(@rule_config, root: @root)
      assert errors.any?
      error = errors.first[:sub_errors].first
      assert_equal :empty_path, error[:error_code]
      assert_equal "File path cannot be empty", error[:message]
    end

    test "returns error if a file path is too long" do
      enable_feature_flag(:file_extension_and_path_limits)
      @rule_config.parameters["restricted_file_paths"] << "a" * 201
      errors = @rule.validate_parameterized(@rule_config, root: @root)
      assert errors.any?
      error = errors.first[:sub_errors].first
      assert_equal :path_too_long, error[:error_code]
      assert_equal "File path is too long (maximum is 200 characters)", error[:message]
    end

    test "errors when there are too many restricted file paths in the ruleset" do
      enable_feature_flag(:file_extension_and_path_limits)
      paths = []
      200.times do
        paths << "*.exe"
      end
      rule_config = build_file_path_restriction_rule_config(paths)

      errors = @rule.validate_parameterized(rule_config, root: @root)
      refute errors.any?

      paths << "*.exe"
      rule_config = build_file_path_restriction_rule_config(paths)
      errors = @rule.validate_parameterized(rule_config, root: @root)
      assert errors.any?
      error = errors.first[:sub_errors].first
      assert_equal :too_many_entries, error[:error_code]
      assert_equal "Limit of 200 file paths reached", error[:message]
    end
  end

  context "#evaluate_candidate" do
    test "returns true if path is not restricted" do
      candidate = create_blob_candidate(path: "test")
      result = @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate).success?

      assert result
    end

    test "returns true if candidate is nil" do
      rule_config = build_file_path_restriction_rule_config(nil)
      candidate = create_blob_candidate(path: "test")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      assert result
    end

    test "returns true if candidate is empty array" do
      rule_config = build_file_path_restriction_rule_config([])
      candidate = create_blob_candidate(path: "test")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      assert result
    end

    test "returns false if path is an exact match restriction" do
      rule_config = build_file_path_restriction_rule_config(["test/restricted.txt"])
      candidate = create_blob_candidate(path: "test/restricted.txt")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      refute result
    end

    test "returns false if path is a single wildcard match restriction" do
      candidate = create_blob_candidate(path: ".github/test.yaml")
      result = @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate).success?

      refute result
    end

    test "returns true if path is a subdirectory and restriction uses single wildcard character" do
      candidate = create_blob_candidate(path: ".github/tests/test.yaml")
      result = @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate).success?

      assert result
    end

    test "returns false for subdirectories when restriction uses double wildcard character" do
      rule_config = build_file_path_restriction_rule_config([".github/**/*"])
      candidate = create_blob_candidate(path: ".github/test.yaml")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      refute result
    end

    test "returns false when there is at least one match" do
      rule_config = build_file_path_restriction_rule_config([".github/*", "tests/**/*", "workflows/**/*"])
      candidate = create_blob_candidate(path: "tests/file_path_restriction_rule_test.rb")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      refute result
    end

    test "returns false for partial match" do
      rule_config = build_file_path_restriction_rule_config(["**/passwords/**/*"])
      candidate = create_blob_candidate(path: "app/test/passwords/secret.txt")
      result = @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate).success?

      refute result
    end

    test "ignores case when matching" do
      rule_config = build_file_path_restriction_rule_config([".GitHub/*"])
      candidate = create_blob_candidate(path: ".GITHUB/test.yaml")
      refute_predicate @rule.evaluate_candidate(@context, @ref_update, rule_config, candidate), :success?
    end
  end

  context "#generate_evaluation_result" do
    test "generates allowed rule run when no violations" do
      result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, [])

      assert_predicate result, :allowed?
    end

    test "generates failed rule run when violations exist" do
      violations = [RuleEngine::Violation.new(candidate: create_blob_candidate(path: ".github/workflow.yaml"))]
      @rule_config.parameters["restricted_file_paths"] << "tests/**/*"
      result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)

      assert_predicate result, :failed?
      assert_equal "File path is restricted", result.message
    end
  end
end
