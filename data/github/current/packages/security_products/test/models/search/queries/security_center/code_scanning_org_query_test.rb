# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityCenterCodeScanningOrgQueryTest < GitHub::TestCase

  context "#repository_names" do
    test "returns all repository values" do
      assert_empty create_query("is:open").repository_names
      assert_empty create_query("repo:").repository_names
      assert_equal ["abc"], create_query("repo:abc").repository_names
      assert_equal %w[abc def], create_query("repo:abc,def").repository_names
      assert_equal %w[abc def], create_query("repo:abc repo:def").repository_names
      assert_equal ["abc"], create_query("repo:abc -repo:def").repository_names
    end
  end

  context "#exclude_repository_names" do
    test "returns a list of excluded repository names" do
      assert_empty create_query("is:open").excluded_repository_names
      assert_empty create_query("-repo:").excluded_repository_names
      assert_empty create_query("repo:abc").excluded_repository_names
      assert_equal %w[abc def], create_query("-repo:abc,def").excluded_repository_names
      assert_equal ["def"], create_query("repo:abc -repo:def").excluded_repository_names
    end
  end

  context "autofixfilter methods" do
    test "it returns the value for autofixfilter" do
      q = create_query("autofix:generated")
      assert_equal "generated", q.autofix
      assert_equal ::Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_GENERATED, q.autofix_enum
      assert q.has_valid_autofix?

      q = create_query("autofix:supported")
      assert_equal "supported", q.autofix
      assert_equal ::Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_SUPPORTED, q.autofix_enum
      assert q.has_valid_autofix?
    end
  end

  def create_query(query)
    Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query)
  end
end
