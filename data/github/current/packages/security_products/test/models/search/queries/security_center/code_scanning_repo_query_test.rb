# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboscan"

class SearchQueriesSecurityCenterCodeScanningRepoQueryTest < GitHub::TestCase

  context "#refs" do
    test "it returns all the ref values" do
      assert_equal [], create_query("is:closed").refs
      assert_equal %w[branch1 master], create_query("is:closed ref:branch1 ref:master").refs
    end
  end

  context "#severity" do
    test "it returns the value for security severity" do
      q = create_query("severity:critical")
      assert_equal "critical", q.severity
      assert_equal ::Turboscan::Proto::SecuritySeverity::CRITICAL, q.security_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:high")
      assert_equal "high", q.severity
      assert_equal ::Turboscan::Proto::SecuritySeverity::HIGH, q.security_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:medium")
      assert_equal "medium", q.severity
      assert_equal ::Turboscan::Proto::SecuritySeverity::MEDIUM, q.security_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:low")
      assert_equal "low", q.severity
      assert_equal ::Turboscan::Proto::SecuritySeverity::LOW, q.security_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:cRiTiCaL")
      assert_equal "cRiTiCaL", q.severity
      assert_equal ::Turboscan::Proto::SecuritySeverity::CRITICAL, q.security_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:foo")
      assert_equal "foo", q.severity
      assert_nil q.security_severity_enum
      refute q.has_valid_severity?

      q = create_query("")
      assert_nil q.severity
      assert_nil q.security_severity_enum
      assert q.has_valid_severity?
    end

    test "it returns the value for rule severity" do
      q = create_query("severity:error")
      assert_equal ::Turboscan::Proto::RuleSeverity::ERROR, q.rule_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:warning")
      assert_equal ::Turboscan::Proto::RuleSeverity::WARNING, q.rule_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:note")
      assert_equal ::Turboscan::Proto::RuleSeverity::NOTE, q.rule_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:eRrOr")
      assert_equal ::Turboscan::Proto::RuleSeverity::ERROR, q.rule_severity_enum
      assert q.has_valid_severity?

      q = create_query("severity:foo")
      assert_equal "foo", q.severity
      assert_nil q.security_severity_enum
      refute q.has_valid_severity?

      q = create_query("")
      assert_nil q.severity
      assert_nil q.security_severity_enum
      assert q.has_valid_severity?
    end
  end

  context "#resolution" do
    test "it returns the value for resolution" do
      q = create_query("resolution:fixed")
      assert_equal ["fixed"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_NO_RESOLUTION], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:false-positive")
      assert_equal ["false-positive"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:used-in-tests")
      assert_equal ["used-in-tests"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_USED_IN_TESTS], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:wont-fix")
      assert_equal ["wont-fix"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_WONT_FIX], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:fIxEd")
      assert_equal ["fIxEd"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_NO_RESOLUTION], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:foo")
      assert_equal ["foo"], q.resolutions
      assert_empty q.resolution_enums
      refute q.has_valid_resolutions?

      q = create_query("")
      assert_empty q.resolutions
      assert_empty q.resolution_enums
      assert q.has_valid_resolutions?
    end
  end

  context "#paths" do
    test "it returns the value for path" do
      q = create_query("path:foo/**/bar")
      assert_equal ["foo/**/bar"], q.paths
      assert q.is_valid?

      q = create_query("path:foo,bar")
      assert_equal %w[foo bar], q.paths
      assert q.is_valid?

      q = create_query("")
      assert_equal [], q.paths
      assert q.is_valid?
    end
  end

  context "#languages" do
    test "it returns the value for language" do
      q = create_query("language:ruby")
      assert_includes q.language_paths, "*.rb"
      assert q.is_valid?

      q = create_query("language:ruby OR language:go")
      assert_includes q.language_paths, "*.rb"
      assert_includes q.language_paths, "*.go"
      assert q.is_valid?

      q = create_query("")
      assert_equal [], q.language_paths
      assert q.is_valid?
    end
  end

  context "#is_valid?" do
    test "an empty query is valid" do
      q = create_query("")
      assert q.is_valid?
    end

    test "a query with unqualified terms is valid" do
      q = create_query("foo")
      # code scanning supports raw query string
      assert q.is_valid?
    end

    test "a query with an unknown qualifier is valid" do
      q = create_query("foo:bar")
      # valid for now; the query parsing doesn't distinguish unknown qualifiers from unqualified terms
      assert q.is_valid?
    end

    test "a query with an invalid state is not valid" do
      q = create_query("is:fake")
      refute q.is_valid?
    end

    test "a query with an invalid severity is not valid" do
      q = create_query("severity:fake")
      refute q.is_valid?
    end

    test "a query with an invalid resolution is not valid" do
      q = create_query("resolution:fake")
      refute q.is_valid?
    end

    test "a query with an invalid autofilter is not valid" do
      q = create_query("autofilter:fake")
      refute q.is_valid?
    end

    test "a query with an invalid sort is valid" do
      q = create_query("sort:fake")
      assert q.is_valid?
    end

    test "a query with an invalid language is not valid" do
      q = create_query("language:Besźel")
      refute q.is_valid?
    end
  end

  def create_query(query)
    Search::Queries::SecurityCenter::CodeScanningRepoQuery.new(query)
  end
end
